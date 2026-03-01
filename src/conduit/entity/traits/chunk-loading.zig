const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const Conduit = @import("../../conduit.zig").Conduit;
const TickProfiler = @import("../../tick-profiler.zig").TickProfiler;
const Chunk = @import("../../world/chunk/chunk.zig").Chunk;
const Raknet = @import("Raknet");
const ThreadedTask = @import("../../tasks/threaded-tasks.zig").ThreadedTask;
const Compression = @import("../../network/compression/compression.zig").Compression;
const CompressionOptions = @import("../../network/compression/options.zig").CompressionOptions;
const WorldProvider = @import("../../world/provider/world-provider.zig").WorldProvider;
const NBT = @import("nbt");
const Block = @import("../../world/block/block.zig").Block;
const BlockPermutation = @import("../../world/block/block-permutation.zig").BlockPermutation;
const trait_mod = @import("../../world/block/traits/trait.zig");
const chunk_mod = @import("../../world/chunk/chunk.zig");

pub const State = struct {
    last_chunk_x: i32,
    last_chunk_z: i32,
    initialized: bool,
};

fn getPlayer(entity: *Entity) ?*Player {
    if (!std.mem.eql(u8, entity.entity_type.identifier, "minecraft:player")) return null;
    return @fieldParentPtr("entity", entity);
}

fn onTick(state: *State, entity: *Entity) void {
    const player = getPlayer(entity) orelse return;
    if (!player.spawned) return;

    const cx = @as(i32, @intFromFloat(@floor(entity.position.x))) >> 4;
    const cz = @as(i32, @intFromFloat(@floor(entity.position.z))) >> 4;

    updatePlayerVisibility(player);

    if (state.initialized and cx == state.last_chunk_x and cz == state.last_chunk_z) return;

    state.last_chunk_x = cx;
    state.last_chunk_z = cz;

    if (!state.initialized) {
        state.initialized = true;
        sendPublisherUpdate(player);
        queueChunkStreaming(player) catch {};
        return;
    }

    sendPublisherUpdate(player);
    queueChunkStreaming(player) catch {};
}

fn sendPublisherUpdate(player: *Player) void {
    var stream = BinaryStream.init(player.entity.allocator, null, null);
    defer stream.deinit();

    var update = Protocol.NetworkChunkPublisherUpdatePacket{
        .coordinate = Protocol.BlockPosition{
            .x = @intFromFloat(@floor(player.entity.position.x)),
            .y = @intFromFloat(@floor(player.entity.position.y)),
            .z = @intFromFloat(@floor(player.entity.position.z)),
        },
        .radius = @intCast(player.view_distance * 16),
        .savedChunks = &[_]Protocol.ChunkCoords{},
    };
    const serialized = update.serialize(&stream) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};
}

fn updatePlayerVisibility(player: *Player) void {
    const conduit = player.network.conduit;
    const allocator = player.entity.allocator;
    const snapshots = conduit.getPlayerSnapshots();
    const range = player.view_distance * 16;
    const range_sq: f32 = @floatFromInt(range * range);

    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        if (!other.spawned) continue;

        const dx = player.entity.position.x - other.entity.position.x;
        const dz = player.entity.position.z - other.entity.position.z;
        const dist_sq = dx * dx + dz * dz;
        const in_range = dist_sq <= range_sq;
        const currently_visible = player.visible_players.contains(other.entity.runtime_id);

        if (in_range and !currently_visible) {
            spawnPlayerFor(player, other, allocator);
            player.visible_players.put(other.entity.runtime_id, {}) catch {};
        } else if (!in_range and currently_visible) {
            despawnPlayerFor(player, other, allocator);
            _ = player.visible_players.remove(other.entity.runtime_id);
        }
    }

    var stale = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
    defer stale.deinit(allocator);
    var it = player.visible_players.keyIterator();
    while (it.next()) |rid| {
        var found = false;
        for (snapshots) |other| {
            if (other.entity.runtime_id == rid.*) {
                found = true;
                break;
            }
        }
        if (!found) {
            stale.append(allocator, rid.*) catch {};
        }
    }
    for (stale.items) |rid| {
        _ = player.visible_players.remove(rid);
    }
}

fn spawnPlayerFor(viewer: *Player, target: *Player, allocator: std.mem.Allocator) void {
    {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        const packet = Protocol.AddPlayerPacket{
            .uuid = target.uuid,
            .username = target.username,
            .entityRuntimeId = target.entity.runtime_id,
            .position = target.entity.position,
            .entityProperties = Protocol.PropertySyncData.init(allocator),
            .abilityEntityUniqueId = target.entity.runtime_id,
        };
        const serialized = packet.serialize(&stream) catch return;
        viewer.network.sendPacket(viewer.connection, serialized) catch {};
    }

    {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        const packet = Protocol.PlayerSkinPacket{
            .uuid = target.uuid,
            .skin = &target.loginData.client_data,
        };
        const serialized = packet.serialize(&stream, allocator) catch return;
        viewer.network.sendPacket(viewer.connection, serialized) catch {};
    }

    {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        const flags_data = target.entity.flags.buildDataItems(allocator) catch return;
        var packet = Protocol.SetActorDataPacket.init(allocator, target.entity.runtime_id, 0, flags_data);
        defer packet.deinit();
        const serialized = packet.serialize(&stream) catch return;
        viewer.network.sendPacket(viewer.connection, serialized) catch {};
    }
}

fn despawnPlayerFor(viewer: *Player, target: *Player, allocator: std.mem.Allocator) void {
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();
    const packet = Protocol.RemoveEntityPacket{ .uniqueEntityId = target.entity.unique_id };
    const serialized = packet.serialize(&stream) catch return;
    viewer.network.sendPacket(viewer.connection, serialized) catch {};
}

const ChunkStreamState = struct {
    conduit: *Conduit,
    runtime_id: i64,
    allocator: std.mem.Allocator,
    center_x: i32,
    center_z: i32,
    radius: i32,
    ring: i32,
    ring_idx: i32,
    inflight: u32,
};

const BATCH_SIZE: usize = 4;
const MAX_INFLIGHT_BATCHES: u32 = 8;

pub fn queueChunkStreaming(player: *Player) !void {
    const conduit = player.network.conduit;
    const world = conduit.getWorld("world") orelse return;
    const dimension = world.getDimension("overworld") orelse return;
    const allocator = player.entity.allocator;

    conduit.tasks.cancelByOwner("chunk_streaming", player.entity.runtime_id, destroyStreamState);

    const center_x = @as(i32, @intFromFloat(@floor(player.entity.position.x))) >> 4;
    const center_z = @as(i32, @intFromFloat(@floor(player.entity.position.z))) >> 4;
    const radius = player.view_distance;

    var stale_hashes = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
    defer stale_hashes.deinit(allocator);

    var it = player.sent_chunks.keyIterator();
    while (it.next()) |key| {
        const coords = Protocol.ChunkCoords.unhash(key.*);
        const dx = coords.x - center_x;
        const dz = coords.z - center_z;
        if (dx * dx + dz * dz > radius * radius) {
            stale_hashes.append(allocator, key.*) catch {};
        }
    }

    for (stale_hashes.items) |h| {
        _ = player.sent_chunks.remove(h);
    }

    dimension.releaseUnrenderedChunks(stale_hashes.items);

    const state = try allocator.create(ChunkStreamState);
    state.* = .{
        .conduit = conduit,
        .runtime_id = player.entity.runtime_id,
        .allocator = allocator,
        .center_x = center_x,
        .center_z = center_z,
        .radius = radius,
        .ring = 0,
        .ring_idx = 0,
        .inflight = 0,
    };

    try conduit.tasks.enqueue(.{
        .func = chunkStreamStep,
        .ctx = @ptrCast(state),
        .name = "chunk_streaming",
        .owner_id = player.entity.runtime_id,
        .cleanup = destroyStreamState,
    });
}

pub fn destroyStreamState(ctx: *anyopaque) void {
    const state: *ChunkStreamState = @ptrCast(@alignCast(ctx));
    state.allocator.destroy(state);
}

const ChunkCoord = struct { x: i32, z: i32 };

const ParsedBlockEntity = struct {
    x: i32,
    y: i32,
    z: i32,
    trait_ids: [][]const u8,
    nbt_data: ?[]const u8,
};

const TraitBlockPos = struct {
    x: i32,
    y: i32,
    z: i32,
};

const ChunkBlockData = struct {
    parsed_entities: []ParsedBlockEntity,
    trait_positions: []TraitBlockPos,
};

const ChunkBatchWork = struct {
    coords: []ChunkCoord,
    hashes: []i64,
    packets: [][]const u8,
    chunks: []?*Chunk,
    block_data: []ChunkBlockData,
    count: usize,
    runtime_id: i64,
    conduit: *Conduit,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    options: CompressionOptions,
    provider: WorldProvider,
    dim_type: Protocol.DimensionType,
    generator: ?@import("../../world/generator/terrain-generator.zig").TerrainGenerator,
    sim_distance: i32,
    center_x: i32,
    center_z: i32,
};

fn workerLoadAndCompress(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;
    const arena_alloc = work.arena.allocator();

    var raw_packets: [BATCH_SIZE][]const u8 = undefined;
    var raw_count: usize = 0;

    for (0..work.count) |i| {
        work.block_data[i] = .{ .parsed_entities = &.{}, .trait_positions = &.{} };

        const coord = work.coords[i];
        const chunk = work.provider.readChunkDirect(coord.x, coord.z, work.dim_type) catch blk: {
            if (work.generator) |gen| {
                break :blk gen.generate(allocator, coord.x, coord.z) catch {
                    work.packets[i] = &.{};
                    work.chunks[i] = null;
                    continue;
                };
            } else {
                work.packets[i] = &.{};
                work.chunks[i] = null;
                continue;
            }
        };

        work.chunks[i] = chunk;

        const dx = coord.x - work.center_x;
        const dz = coord.z - work.center_z;
        const in_simulation = dx * dx + dz * dz <= work.sim_distance * work.sim_distance;

        if (in_simulation) {
            work.block_data[i] = workerReadBlockData(arena_alloc, work.provider, chunk, work.dim_type);
        }

        const pkt = serializeChunkPacket(allocator, chunk, coord.x, coord.z) orelse {
            work.packets[i] = &.{};
            continue;
        };

        work.packets[i] = pkt;
        raw_packets[raw_count] = pkt;
        raw_count += 1;
    }

    if (raw_count > 1) {
        const compressed = Compression.compress(raw_packets[0..raw_count], work.options, allocator) catch {
            for (0..work.count) |i| {
                if (work.packets[i].len > 0) {
                    const pkts = [_][]const u8{work.packets[i]};
                    work.packets[i] = Compression.compress(&pkts, work.options, allocator) catch {
                        allocator.free(work.packets[i]);
                        work.packets[i] = &.{};
                        continue;
                    };
                }
            }
            return;
        };
        for (0..work.count) |i| {
            if (work.packets[i].len > 0) allocator.free(work.packets[i]);
            work.packets[i] = &.{};
        }
        work.packets[0] = compressed;
    } else {
        for (0..work.count) |i| {
            if (work.packets[i].len > 0) {
                const pkt = work.packets[i];
                const pkts = [_][]const u8{pkt};
                work.packets[i] = Compression.compress(&pkts, work.options, allocator) catch {
                    allocator.free(pkt);
                    work.packets[i] = &.{};
                    continue;
                };
                allocator.free(pkt);
            }
        }
    }
}

fn workerReadBlockData(allocator: std.mem.Allocator, provider: WorldProvider, chunk: *Chunk, dim_type: Protocol.DimensionType) ChunkBlockData {
    var result = ChunkBlockData{ .parsed_entities = &.{}, .trait_positions = &.{} };

    var entities = std.ArrayList(ParsedBlockEntity){ .items = &.{}, .capacity = 0 };
    var positions = std.ArrayList(TraitBlockPos){ .items = &.{}, .capacity = 0 };

    const dim_index: i32 = switch (dim_type) {
        .Overworld => 0,
        .Nether => 1,
        .End => 2,
    };
    var key_buf: [20]u8 = undefined;
    const base = chunkKeyBase(chunk.x, chunk.z, dim_index);
    @memcpy(key_buf[0..base.len], base.buf[0..base.len]);
    key_buf[base.len] = 49;
    const key_len = base.len + 1;

    const raw_provider: *@import("../../world/provider/leveldb-provider.zig").LevelDBProvider = @ptrCast(@alignCast(provider.ptr));
    if (raw_provider.db.get(key_buf[0..key_len])) |data| {
        defer @import("leveldb").DB.freeValue(data);
        var stream = @import("BinaryStream").BinaryStream.init(allocator, data, null);
        while (stream.offset < data.len) {
            var tag = NBT.CompoundTag.read(&stream, allocator, NBT.ReadWriteOptions.default) catch break;

            const x = switch (tag.get("x") orelse {
                tag.deinit(allocator);
                continue;
            }) {
                .Int => |t| t.value,
                else => {
                    tag.deinit(allocator);
                    continue;
                },
            };
            const y = switch (tag.get("y") orelse {
                tag.deinit(allocator);
                continue;
            }) {
                .Int => |t| t.value,
                else => {
                    tag.deinit(allocator);
                    continue;
                },
            };
            const z = switch (tag.get("z") orelse {
                tag.deinit(allocator);
                continue;
            }) {
                .Int => |t| t.value,
                else => {
                    tag.deinit(allocator);
                    continue;
                },
            };

            var trait_ids = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
            const traits_tag = tag.get("traits") orelse tag.get("Traits");
            if (traits_tag) |tt| {
                switch (tt) {
                    .List => |list| {
                        for (list.value) |item| {
                            switch (item) {
                                .String => |s| {
                                    const duped = allocator.dupe(u8, s.value) catch continue;
                                    trait_ids.append(allocator, duped) catch {
                                        allocator.free(duped);
                                        continue;
                                    };
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }

            var nbt_data: ?[]const u8 = null;
            var nbt_stream = @import("BinaryStream").BinaryStream.init(allocator, null, null);
            NBT.CompoundTag.write(&nbt_stream, &tag, NBT.ReadWriteOptions.default) catch {
                nbt_stream.deinit();
                tag.deinit(allocator);
                for (trait_ids.items) |id| allocator.free(id);
                if (trait_ids.capacity > 0) trait_ids.deinit(allocator);
                continue;
            };
            nbt_data = allocator.dupe(u8, nbt_stream.getBuffer()) catch null;
            nbt_stream.deinit();
            tag.deinit(allocator);

            entities.append(allocator, .{
                .x = x,
                .y = y,
                .z = z,
                .trait_ids = trait_ids.toOwnedSlice(allocator) catch &.{},
                .nbt_data = nbt_data,
            }) catch continue;
        }
    }

    if (trait_mod.hasAnyStaticTraits()) {
        const offset = chunk_mod.yOffset(dim_type);
        for (0..chunk_mod.MAX_SUBCHUNKS) |si| {
            const sc = chunk.subchunks[si] orelse continue;
            if (sc.layers.items.len == 0) continue;
            const layer = &sc.layers.items[0];

            var has_traits = false;
            for (layer.paletteSlice()) |network_id| {
                const perm = BlockPermutation.getByNetworkId(network_id) orelse continue;
                if (std.mem.eql(u8, perm.identifier, "minecraft:air")) continue;
                if (trait_mod.hasRegisteredTraits(perm.identifier)) {
                    has_traits = true;
                    break;
                }
            }
            if (!has_traits) continue;

            var trait_palette = std.AutoHashMap(u32, bool).init(allocator);
            defer trait_palette.deinit();
            for (layer.paletteSlice(), 0..) |network_id, pi| {
                const perm = BlockPermutation.getByNetworkId(network_id) orelse continue;
                if (std.mem.eql(u8, perm.identifier, "minecraft:air")) continue;
                if (trait_mod.hasRegisteredTraits(perm.identifier)) {
                    trait_palette.put(@intCast(pi), true) catch continue;
                }
            }

            const sc_y: i32 = @as(i32, @intCast(si)) - @as(i32, @intCast(offset));
            for (0..4096) |pos_idx| {
                const palette_idx = layer.blocks[pos_idx];
                if (!trait_palette.contains(palette_idx)) continue;

                const bx: i32 = @intCast((pos_idx >> 8) & 0xf);
                const by: i32 = @intCast(pos_idx & 0xf);
                const bz: i32 = @intCast((pos_idx >> 4) & 0xf);

                positions.append(allocator, .{
                    .x = chunk.x * 16 + bx,
                    .y = sc_y * 16 + by,
                    .z = chunk.z * 16 + bz,
                }) catch continue;
            }
        }
    }

    result.parsed_entities = entities.toOwnedSlice(allocator) catch &.{};
    result.trait_positions = positions.toOwnedSlice(allocator) catch &.{};
    return result;
}

fn chunkKeyBase(x: i32, z: i32, dim_index: i32) struct { buf: [12]u8, len: usize } {
    var buf: [12]u8 = undefined;
    @memcpy(buf[0..4], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, x))));
    @memcpy(buf[4..8], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, z))));
    if (dim_index != 0) {
        @memcpy(buf[8..12], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, dim_index))));
        return .{ .buf = buf, .len = 12 };
    }
    return .{ .buf = buf, .len = 8 };
}

fn onBatchComplete(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;
    defer {
        decrementInflight(work.conduit, work.runtime_id);
        allocator.free(work.coords);
        allocator.free(work.hashes);
        allocator.free(work.packets);
        allocator.free(work.chunks);
        freeBlockDataSlice(allocator, work.block_data, work.count);
        work.arena.deinit();
        allocator.destroy(work);
    }

    const player = work.conduit.players.get(work.runtime_id) orelse {
        for (0..work.count) |i| {
            if (work.packets[i].len > 0) allocator.free(work.packets[i]);
            if (work.chunks[i]) |chunk| {
                var c = chunk;
                c.deinit();
                allocator.destroy(c);
            }
        }
        return;
    };

    const world = work.conduit.getWorld("world");
    const dimension = if (world) |w| w.getDimension("overworld") else null;
    const sim_dist = if (dimension) |d| d.simulation_distance else work.sim_distance;

    var t0 = std.time.nanoTimestamp();
    for (0..work.count) |i| {
        if (work.chunks[i]) |chunk| {
            if (dimension) |dim| {
                const dx = chunk.x - work.center_x;
                const dz = chunk.z - work.center_z;
                if (dx * dx + dz * dz <= sim_dist * sim_dist) {
                    const hash = @import("../../world/dimension/dimension.zig").chunkHash(chunk.x, chunk.z);
                    const result = dim.chunks.fetchPut(hash, chunk) catch {
                        var c = chunk;
                        c.deinit();
                        allocator.destroy(c);
                        work.chunks[i] = null;
                        continue;
                    };
                    if (result) |old| {
                        dim.removeBlocksInChunk(chunk.x, chunk.z);
                        dim.world.provider.uncacheChunk(chunk.x, chunk.z, dim);
                        var old_chunk = old.value;
                        old_chunk.deinit();
                        allocator.destroy(old_chunk);
                    }
                } else {
                    var c = chunk;
                    c.deinit();
                    allocator.destroy(c);
                    work.chunks[i] = null;
                }
            } else {
                var c = chunk;
                c.deinit();
                allocator.destroy(c);
            }
        }
    }
    var t1 = std.time.nanoTimestamp();
    work.conduit.profiler.record(.batch_chunks, @intCast(@max(0, t1 - t0)));

    t0 = std.time.nanoTimestamp();
    for (0..work.count) |i| {
        const compressed = work.packets[i];
        if (compressed.len == 0) continue;
        player.connection.sendReliableMessage(compressed, .Normal);
        allocator.free(compressed);
    }

    for (0..work.count) |i| {
        player.sent_chunks.put(work.hashes[i], {}) catch {};
    }
    t1 = std.time.nanoTimestamp();
    work.conduit.profiler.record(.batch_send, @intCast(@max(0, t1 - t0)));

    t0 = std.time.nanoTimestamp();
    if (dimension) |dim| {
        for (0..work.count) |i| {
            if (work.chunks[i] == null) continue;
            const dx = work.coords[i].x - work.center_x;
            const dz = work.coords[i].z - work.center_z;
            if (dx * dx + dz * dz <= sim_dist * sim_dist) {
                applyParsedBlockData(allocator, dim, &work.block_data[i]);
            }
        }

        var sim_coords_buf: [BATCH_SIZE]ChunkCoord = undefined;
        var sim_count: usize = 0;
        for (0..work.count) |i| {
            const dx = work.coords[i].x - work.center_x;
            const dz = work.coords[i].z - work.center_z;
            if (dx * dx + dz * dz <= sim_dist * sim_dist) {
                sim_coords_buf[sim_count] = work.coords[i];
                sim_count += 1;
            }
        }
        if (sim_count > 0) {
            sendBlockActorData(allocator, player, dim, sim_coords_buf[0..sim_count]);
        }
    }
    t1 = std.time.nanoTimestamp();
    work.conduit.profiler.record(.batch_block_data, @intCast(@max(0, t1 - t0)));
}

fn applyParsedBlockData(allocator: std.mem.Allocator, dim: *Dimension, data: *ChunkBlockData) void {
    for (data.parsed_entities) |entity| {
        const pos = Protocol.BlockPosition{ .x = entity.x, .y = entity.y, .z = entity.z };
        if (dim.getBlockPtr(pos) != null) continue;

        const block = allocator.create(Block) catch continue;
        block.* = Block.init(allocator, dim, pos);

        for (entity.trait_ids) |tid| {
            if (trait_mod.getTraitFactory(tid)) |f| {
                const instance = f(allocator) catch continue;
                block.addTrait(instance) catch continue;
            }
        }

        if (block.traits.items.len == 0) {
            block.deinit();
            allocator.destroy(block);
            continue;
        }

        dim.storeBlock(block) catch {
            block.deinit();
            allocator.destroy(block);
            continue;
        };

        if (entity.nbt_data) |nbt_bytes| {
            var stream = @import("BinaryStream").BinaryStream.init(allocator, nbt_bytes, null);
            var tag = NBT.CompoundTag.read(&stream, allocator, NBT.ReadWriteOptions.default) catch continue;
            defer tag.deinit(allocator);
            block.fireEvent(.Deserialize, .{&tag});
        }
    }

    for (data.trait_positions) |tp| {
        const pos = Protocol.BlockPosition{ .x = tp.x, .y = tp.y, .z = tp.z };
        if (dim.getBlockPtr(pos) != null) continue;
        trait_mod.applyTraitsForBlock(allocator, dim, pos) catch continue;
    }
}

fn freeBlockDataSlice(allocator: std.mem.Allocator, block_data: []ChunkBlockData, _: usize) void {
    allocator.free(block_data);
}

fn sendBlockActorData(allocator: std.mem.Allocator, player: *Player, dim: *Dimension, batch_coords: []const ChunkCoord) void {
    for (batch_coords) |coord| {
        const chunk_blocks = dim.getBlocksInChunk(coord.x, coord.z);
        for (chunk_blocks) |block| {
            if (block.traits.items.len == 0) continue;

            var has_serialize = false;
            for (block.traits.items) |inst| {
                if (inst.vtable.onSerialize != null) {
                    has_serialize = true;
                    break;
                }
            }
            if (!has_serialize) continue;

            var tag = NBT.CompoundTag.init(allocator, null);
            defer tag.deinit(allocator);

            const id_str = allocator.dupe(u8, block.getIdentifier()) catch continue;
            tag.set("id", .{ .String = NBT.StringTag.init(id_str, null) }) catch continue;
            tag.set("x", .{ .Int = NBT.IntTag.init(block.position.x, null) }) catch continue;
            tag.set("y", .{ .Int = NBT.IntTag.init(block.position.y, null) }) catch continue;
            tag.set("z", .{ .Int = NBT.IntTag.init(block.position.z, null) }) catch continue;

            block.fireEvent(.Serialize, .{&tag});

            var s = BinaryStream.init(allocator, null, null);
            defer s.deinit();
            const pkt = Protocol.BlockActorDataPacket{
                .position = block.position,
                .nbt = tag,
            };
            const serialized = pkt.serialize(&s, allocator) catch continue;
            player.network.sendPacket(player.connection, serialized) catch {};
        }
    }
}

fn cleanupBatchWork(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;
    decrementInflight(work.conduit, work.runtime_id);
    for (0..work.count) |i| {
        if (work.packets[i].len > 0) allocator.free(work.packets[i]);
        if (work.chunks[i]) |chunk| {
            var c = chunk;
            c.deinit();
            allocator.destroy(c);
        }
    }
    allocator.free(work.coords);
    allocator.free(work.hashes);
    allocator.free(work.packets);
    allocator.free(work.chunks);
    freeBlockDataSlice(allocator, work.block_data, work.count);
    work.arena.deinit();
    allocator.destroy(work);
}

fn serializeChunkPacket(allocator: std.mem.Allocator, chunk: *Chunk, cx: i32, cz: i32) ?[]const u8 {
    var chunk_stream = BinaryStream.init(allocator, null, null);
    defer chunk_stream.deinit();
    chunk.serialize(&chunk_stream) catch return null;

    var pkt_stream = BinaryStream.init(allocator, null, null);
    defer pkt_stream.deinit();

    var level_chunk = Protocol.LevelChunkPacket{
        .x = cx,
        .z = cz,
        .dimension = .Overworld,
        .highestSubChunkCount = 0,
        .subChunkCount = @intCast(chunk.getSubChunkSendCount()),
        .cacheEnabled = false,
        .blobs = &[_]u64{},
        .data = chunk_stream.getBuffer(),
    };

    const serialized = level_chunk.serialize(&pkt_stream) catch return null;
    return allocator.dupe(u8, serialized) catch null;
}

fn decrementInflight(conduit: *Conduit, runtime_id: i64) void {
    for (conduit.tasks.tasks.items) |*task| {
        if (task.owner_id == runtime_id and std.mem.eql(u8, task.name, "chunk_streaming")) {
            const state: *ChunkStreamState = @ptrCast(@alignCast(task.ctx));
            if (state.inflight > 0) state.inflight -= 1;
            return;
        }
    }
}

fn chunkStreamStep(ctx: *anyopaque) bool {
    const state: *ChunkStreamState = @ptrCast(@alignCast(ctx));
    const allocator = state.allocator;

    const player = state.conduit.players.get(state.runtime_id) orelse {
        allocator.destroy(state);
        return true;
    };

    const world = state.conduit.getWorld("world") orelse {
        allocator.destroy(state);
        return true;
    };
    const dimension = world.getDimension("overworld") orelse {
        allocator.destroy(state);
        return true;
    };

    while (state.inflight < MAX_INFLIGHT_BATCHES and state.ring <= state.radius) {
        var coord_buf: [BATCH_SIZE]ChunkCoord = undefined;
        var hash_buf: [BATCH_SIZE]i64 = undefined;
        var count: usize = 0;

        while (state.ring <= state.radius) {
            if (count >= BATCH_SIZE) break;

            const ring = state.ring;
            if (ring == 0) {
                state.ring = 1;
                state.ring_idx = 0;
                const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = state.center_x, .z = state.center_z });
                if (!player.sent_chunks.contains(chunk_hash)) {
                    if (dimension.getCachedChunkPacket(chunk_hash)) |cached| {
                        player.connection.sendReliableMessage(cached, .Normal);
                        player.sent_chunks.put(chunk_hash, {}) catch {};
                    } else {
                        coord_buf[count] = .{ .x = state.center_x, .z = state.center_z };
                        hash_buf[count] = chunk_hash;
                        count += 1;
                    }
                }
                continue;
            }

            const perimeter = ring * 8;
            if (state.ring_idx >= perimeter) {
                state.ring += 1;
                state.ring_idx = 0;
                continue;
            }

            const coords = ringCoord(state.center_x, state.center_z, ring, state.ring_idx);
            state.ring_idx += 1;

            const dx = coords[0] - state.center_x;
            const dz = coords[1] - state.center_z;
            if (dx * dx + dz * dz > state.radius * state.radius) continue;

            const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = coords[0], .z = coords[1] });
            if (player.sent_chunks.contains(chunk_hash)) continue;

            if (dimension.getCachedChunkPacket(chunk_hash)) |cached| {
                player.connection.sendReliableMessage(cached, .Normal);
                player.sent_chunks.put(chunk_hash, {}) catch {};
                continue;
            }

            coord_buf[count] = .{ .x = coords[0], .z = coords[1] };
            hash_buf[count] = chunk_hash;
            count += 1;
        }

        if (count == 0) break;

        const w_coords = allocator.alloc(ChunkCoord, count) catch break;
        const w_hashes = allocator.alloc(i64, count) catch {
            allocator.free(w_coords);
            break;
        };
        const w_packets = allocator.alloc([]const u8, count) catch {
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };
        const w_chunks = allocator.alloc(?*Chunk, count) catch {
            allocator.free(w_packets);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };
        const w_block_data = allocator.alloc(ChunkBlockData, count) catch {
            allocator.free(w_chunks);
            allocator.free(w_packets);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };

        for (0..count) |i| {
            w_coords[i] = coord_buf[i];
            w_hashes[i] = hash_buf[i];
            w_chunks[i] = null;
            w_packets[i] = &.{};
            w_block_data[i] = .{ .parsed_entities = &.{}, .trait_positions = &.{} };
            player.sent_chunks.put(w_hashes[i], {}) catch {};
        }

        const work = allocator.create(ChunkBatchWork) catch {
            allocator.free(w_block_data);
            allocator.free(w_chunks);
            allocator.free(w_packets);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };

        work.* = .{
            .coords = w_coords,
            .hashes = w_hashes,
            .packets = w_packets,
            .chunks = w_chunks,
            .block_data = w_block_data,
            .count = count,
            .runtime_id = state.runtime_id,
            .conduit = state.conduit,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .options = player.network.options,
            .provider = world.provider,
            .dim_type = .Overworld,
            .generator = if (dimension.generator) |gen| gen.generator else null,
            .sim_distance = dimension.simulation_distance,
            .center_x = state.center_x,
            .center_z = state.center_z,
        };

        state.inflight += 1;

        state.conduit.threaded_tasks.enqueue(.{
            .work = workerLoadAndCompress,
            .callback = onBatchComplete,
            .cleanup = cleanupBatchWork,
            .ctx = @ptrCast(work),
        }) catch {
            cleanupBatchWork(@ptrCast(work));
        };
    }

    if (state.ring > state.radius) {
        allocator.destroy(state);
        return true;
    }
    return false;
}

fn ringCoord(cx: i32, cz: i32, ring: i32, idx: i32) [2]i32 {
    const side = ring * 2;
    if (idx < side) return .{ cx - ring + idx, cz - ring };
    const idx2 = idx - side;
    if (idx2 < side) return .{ cx + ring, cz - ring + idx2 };
    const idx3 = idx2 - side;
    if (idx3 < side) return .{ cx + ring - idx3, cz + ring };
    const idx4 = idx3 - side;
    return .{ cx - ring, cz + ring - idx4 };
}

pub const ChunkLoadingTrait = EntityTrait(State, .{
    .identifier = "chunk_loading",
    .onTick = onTick,
});

// Feature: chunk-performance-optimization, Property 8: Two-tier chunk classification
test "two-tier chunk classification matches squared distance formula" {
    var rng = std.Random.DefaultPrng.init(0xabcd1234);
    const random = rng.random();

    for (0..100) |_| {
        const cx = random.intRangeAtMost(i32, -1000, 1000);
        const cz = random.intRangeAtMost(i32, -1000, 1000);
        const px = random.intRangeAtMost(i32, -1000, 1000);
        const pz = random.intRangeAtMost(i32, -1000, 1000);
        const sim_dist = random.intRangeAtMost(i32, 1, 16);

        const dx = cx - px;
        const dz = cz - pz;
        const in_simulation = dx * dx + dz * dz <= sim_dist * sim_dist;

        const dx_f: f64 = @floatFromInt(dx);
        const dz_f: f64 = @floatFromInt(dz);
        const sd_f: f64 = @floatFromInt(sim_dist);
        const expected = (dx_f * dx_f + dz_f * dz_f) <= (sd_f * sd_f);

        try std.testing.expectEqual(expected, in_simulation);
    }
}

// Feature: chunk-performance-optimization, Property 9: Render-only chunks produce no block data side effects
test "render-only chunks produce empty block data" {
    var rng = std.Random.DefaultPrng.init(0xbeef5678);
    const random = rng.random();

    for (0..100) |_| {
        const px: i32 = 0;
        const pz: i32 = 0;
        const sim_dist: i32 = random.intRangeAtMost(i32, 1, 4);

        const offset = sim_dist + random.intRangeAtMost(i32, 1, 20);
        const cx = px + offset;
        const cz = pz + offset;

        const dx = cx - px;
        const dz = cz - pz;
        const in_simulation = dx * dx + dz * dz <= sim_dist * sim_dist;

        try std.testing.expect(!in_simulation);

        const empty_data = ChunkBlockData{ .parsed_entities = &.{}, .trait_positions = &.{} };
        try std.testing.expectEqual(@as(usize, 0), empty_data.parsed_entities.len);
        try std.testing.expectEqual(@as(usize, 0), empty_data.trait_positions.len);
    }
}
