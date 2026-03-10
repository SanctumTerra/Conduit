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
const BlockState = @import("../../world/block/block-permutation.zig").BlockState;
const BlockType = @import("../../world/block/block-type.zig").BlockType;
const ChestTrait = @import("../../world/block/traits/chest.zig");
const trait_mod = @import("../../world/block/traits/trait.zig");
const chunk_mod = @import("../../world/chunk/chunk.zig");
const LevelDBProvider = @import("../../world/provider/leveldb-provider.zig").LevelDBProvider;
const ChunkColumnData = @import("../../world/provider/leveldb-provider.zig").ChunkColumnData;
const SubChunk = @import("../../world/chunk/subchunk.zig").SubChunk;

pub const State = struct {
    last_chunk_x: i32,
    last_chunk_z: i32,
    initialized: bool,
    visibility_tick: u8,
};

pub const VISIBILITY_UPDATE_INTERVAL: u8 = 4;

fn getPlayer(entity: *Entity) ?*Player {
    if (!std.mem.eql(u8, entity.entity_type.identifier, "minecraft:player")) return null;
    return @fieldParentPtr("entity", entity);
}

fn onTick(state: *State, entity: *Entity) void {
    const player = getPlayer(entity) orelse return;
    if (!player.spawned) return;
    const player_count = player.network.conduit.getPlayerCount();
    const visibility_interval: u8 = if (player_count <= 16)
        VISIBILITY_UPDATE_INTERVAL
    else if (player_count <= 48)
        10
    else
        20;

    const cx = @as(i32, @intFromFloat(@floor(entity.position.x))) >> 4;
    const cz = @as(i32, @intFromFloat(@floor(entity.position.z))) >> 4;
    const moved_chunks = !state.initialized or cx != state.last_chunk_x or cz != state.last_chunk_z;

    state.visibility_tick +%= 1;
    if (moved_chunks or state.visibility_tick >= visibility_interval) {
        state.visibility_tick = 0;
        updatePlayerVisibility(player);
    }

    if (!moved_chunks) return;

    state.last_chunk_x = cx;
    state.last_chunk_z = cz;

    if (!state.initialized) {
        state.initialized = true;
        player.sent_chunks.clearRetainingCapacity();
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

        const currently_visible = player.visible_players.contains(other.entity.runtime_id);

        if (other.entity.dimension != player.entity.dimension) {
            if (currently_visible) {
                despawnPlayerFor(player, other, allocator);
                _ = player.visible_players.remove(other.entity.runtime_id);
            }
            continue;
        }

        const dx = player.entity.position.x - other.entity.position.x;
        const dz = player.entity.position.z - other.entity.position.z;
        const dist_sq = dx * dx + dz * dz;
        const in_range = dist_sq <= range_sq;

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
    dimension: *Dimension,
    runtime_id: i64,
    allocator: std.mem.Allocator,
    center_x: i32,
    center_z: i32,
    radius: i32,
    ring: i32,
    ring_idx: i32,
    inflight: u32,
    upgrade_coords: []ChunkCoord,
    upgrade_hashes: []i64,
    upgrade_idx: usize,
};

// Keep chunk streaming responsive without letting movement flood RakNet.
const BATCH_SIZE: usize = 2;
const MAX_INFLIGHT_BATCHES: u32 = 4;

pub fn queueChunkStreaming(player: *Player) !void {
    const conduit = player.network.conduit;
    const dimension = player.entity.dimension orelse return;
    const allocator = player.entity.allocator;

    conduit.tasks.cancelByOwner("chunk_streaming", player.entity.runtime_id, destroyStreamState);

    const center_x = @as(i32, @intFromFloat(@floor(player.entity.position.x))) >> 4;
    const center_z = @as(i32, @intFromFloat(@floor(player.entity.position.z))) >> 4;
    const radius = player.view_distance;
    const sim_dist = dimension.simulation_distance;

    var stale_hashes = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
    defer stale_hashes.deinit(allocator);
    var upgrade_hashes = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
    defer upgrade_hashes.deinit(allocator);

    var it = player.sent_chunks.keyIterator();
    while (it.next()) |key| {
        const coords = Protocol.ChunkCoords.unhash(key.*);
        const dx = coords.x - center_x;
        const dz = coords.z - center_z;
        if (dx * dx + dz * dz > radius * radius) {
            stale_hashes.append(allocator, key.*) catch {};
            continue;
        }

        if (dx * dx + dz * dz <= sim_dist * sim_dist and dimension.getChunk(coords.x, coords.z) == null) {
            // This chunk was previously sent as render-only data. Once it enters
            // simulation range, force a full reload so block entities exist again.
            upgrade_hashes.append(allocator, key.*) catch {};
        }
    }

    for (stale_hashes.items) |h| {
        _ = player.sent_chunks.remove(h);
    }
    dimension.releaseUnrenderedChunks(stale_hashes.items);

    const state_upgrade_coords = allocator.alloc(ChunkCoord, upgrade_hashes.items.len) catch return error.OutOfMemory;
    errdefer allocator.free(state_upgrade_coords);
    const state_upgrade_hashes = allocator.alloc(i64, upgrade_hashes.items.len) catch return error.OutOfMemory;
    errdefer allocator.free(state_upgrade_hashes);

    for (upgrade_hashes.items, 0..) |h, i| {
        const coords = Protocol.ChunkCoords.unhash(h);
        state_upgrade_coords[i] = .{ .x = coords.x, .z = coords.z };
        state_upgrade_hashes[i] = h;
    }

    const state = try allocator.create(ChunkStreamState);
    state.* = .{
        .conduit = conduit,
        .dimension = dimension,
        .runtime_id = player.entity.runtime_id,
        .allocator = allocator,
        .center_x = center_x,
        .center_z = center_z,
        .radius = radius,
        .ring = 0,
        .ring_idx = 0,
        .inflight = 0,
        .upgrade_coords = state_upgrade_coords,
        .upgrade_hashes = state_upgrade_hashes,
        .upgrade_idx = 0,
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
    state.allocator.free(state.upgrade_coords);
    state.allocator.free(state.upgrade_hashes);
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

fn shouldReadTraitPositions(in_simulation: bool) bool {
    return in_simulation;
}

fn shouldCacheChunkPacket(in_simulation: bool, data: *const ChunkBlockData) bool {
    return !in_simulation and data.parsed_entities.len == 0;
}

const ChunkBatchWork = struct {
    coords: []ChunkCoord,
    hashes: []i64,
    in_simulation: []bool,
    send_chunk_packets: bool,
    packets: [][]const u8,
    cached_packets: [][]const u8,
    chunks: []?*Chunk,
    block_data: []ChunkBlockData,
    count: usize,
    runtime_id: i64,
    conduit: *Conduit,
    dimension: *Dimension,
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
    const raw_provider: *LevelDBProvider = @ptrCast(@alignCast(work.provider.ptr));

    var raw_packets: [BATCH_SIZE][]const u8 = undefined;
    var raw_count: usize = 0;

    for (0..work.count) |i| {
        work.block_data[i] = .{ .parsed_entities = &.{}, .trait_positions = &.{} };

        const coord = work.coords[i];
        if (!work.in_simulation[i] and work.send_chunk_packets) {
            const column = raw_provider.readChunkColumn(coord.x, coord.z, work.dim_type, true) catch null;
            if (column) |loaded_column| {
                var chunk_column = loaded_column;
                defer chunk_column.deinit(raw_provider.allocator);

                work.block_data[i] = .{
                    .parsed_entities = if (chunk_column.block_entity_data) |data|
                        parseBlockEntitiesFromBytes(arena_alloc, data)
                    else
                        &.{},
                    .trait_positions = &.{},
                };

                const pkt = serializeChunkPacketFromColumnWithAllocator(
                    allocator,
                    arena_alloc,
                    &chunk_column,
                    coord.x,
                    coord.z,
                    work.dim_type,
                ) orelse {
                    work.packets[i] = &.{};
                    continue;
                };

                if (shouldCacheChunkPacket(false, &work.block_data[i])) {
                    const single = [_][]const u8{pkt};
                    work.cached_packets[i] = Compression.compress(&single, work.options, allocator) catch &.{};
                }

                work.packets[i] = pkt;
                raw_packets[raw_count] = pkt;
                raw_count += 1;
                work.chunks[i] = null;
                continue;
            }
        }

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

        work.block_data[i] = workerReadBlockData(
            arena_alloc,
            work.provider,
            chunk,
            work.dim_type,
            shouldReadTraitPositions(work.in_simulation[i]),
        );

        if (work.send_chunk_packets) {
            const pkt = serializeChunkPacket(allocator, chunk, coord.x, coord.z, work.dim_type) orelse {
                work.packets[i] = &.{};
                continue;
            };

            if (shouldCacheChunkPacket(work.in_simulation[i], &work.block_data[i])) {
                const single = [_][]const u8{pkt};
                work.cached_packets[i] = Compression.compress(&single, work.options, allocator) catch &.{};
            }

            work.packets[i] = pkt;
            raw_packets[raw_count] = pkt;
            raw_count += 1;
        }
    }

    if (!work.send_chunk_packets) return;

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

fn workerReadBlockData(
    allocator: std.mem.Allocator,
    provider: WorldProvider,
    chunk: *Chunk,
    dim_type: Protocol.DimensionType,
    include_trait_positions: bool,
) ChunkBlockData {
    var result = ChunkBlockData{ .parsed_entities = &.{}, .trait_positions = &.{} };

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

    const raw_provider: *LevelDBProvider = @ptrCast(@alignCast(provider.ptr));
    if (raw_provider.db.get(key_buf[0..key_len])) |data| {
        defer @import("leveldb").DB.freeValue(data);
        result.parsed_entities = parseBlockEntitiesFromBytes(allocator, data);
    }

    if (include_trait_positions and trait_mod.hasAnyStaticTraits()) {
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

fn parseBlockEntitiesFromBytes(allocator: std.mem.Allocator, data: []const u8) []ParsedBlockEntity {
    var entities = std.ArrayList(ParsedBlockEntity){ .items = &.{}, .capacity = 0 };
    var stream = BinaryStream.init(allocator, data, null);
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
        var nbt_stream = BinaryStream.init(allocator, null, null);
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

    return entities.toOwnedSlice(allocator) catch &.{};
}

fn buildChunkFromColumn(allocator: std.mem.Allocator, column: *const ChunkColumnData, x: i32, z: i32, dim_type: Protocol.DimensionType) !Chunk {
    var chunk = Chunk.init(allocator, x, z, dim_type);
    for (column.subchunks, 0..) |maybe_data, i| {
        const data = maybe_data orelse continue;
        var stream = BinaryStream.init(allocator, data, null);
        const sc = try allocator.create(SubChunk);
        errdefer allocator.destroy(sc);
        sc.* = try SubChunk.deserialize(&stream, allocator);
        chunk.subchunks[i] = sc;
    }
    return chunk;
}

fn serializeChunkPacketFromColumnWithAllocator(
    packet_allocator: std.mem.Allocator,
    temp_allocator: std.mem.Allocator,
    column: *const ChunkColumnData,
    cx: i32,
    cz: i32,
    dim_type: Protocol.DimensionType,
) ?[]const u8 {
    var chunk = buildChunkFromColumn(temp_allocator, column, cx, cz, dim_type) catch return null;
    return serializeChunkPacket(packet_allocator, &chunk, cx, cz, dim_type);
}

fn serializeChunkPacketFromColumn(
    allocator: std.mem.Allocator,
    column: *const ChunkColumnData,
    cx: i32,
    cz: i32,
    dim_type: Protocol.DimensionType,
) ?[]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return serializeChunkPacketFromColumnWithAllocator(allocator, arena.allocator(), column, cx, cz, dim_type);
}

fn onBatchComplete(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;
    defer {
        decrementInflight(work.conduit, work.runtime_id);
        allocator.free(work.coords);
        allocator.free(work.hashes);
        allocator.free(work.in_simulation);
        allocator.free(work.packets);
        allocator.free(work.cached_packets);
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

    if (player.entity.dimension != work.dimension) {
        for (0..work.count) |i| {
            if (work.packets[i].len > 0) allocator.free(work.packets[i]);
            if (work.chunks[i]) |chunk| {
                var c = chunk;
                c.deinit();
                allocator.destroy(c);
            }
        }
        return;
    }

    const dimension: ?*Dimension = work.dimension;

    var t0 = std.time.nanoTimestamp();
    for (0..work.count) |i| {
        if (work.chunks[i]) |chunk| {
            if (dimension) |dim| {
                if (work.in_simulation[i]) {
                    const hash = @import("../../world/dimension/dimension.zig").chunkHash(chunk.x, chunk.z);
                    if (dim.chunks.get(hash) != null) {
                        var c = chunk;
                        c.deinit();
                        allocator.destroy(c);
                        work.chunks[i] = null;
                        continue;
                    }
                    dim.chunks.put(hash, chunk) catch {
                        var c = chunk;
                        c.deinit();
                        allocator.destroy(c);
                        work.chunks[i] = null;
                        continue;
                    };
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
    if (work.send_chunk_packets) {
        if (dimension) |dim| {
            for (0..work.count) |i| {
                if (work.in_simulation[i]) continue;
                const cached = work.cached_packets[i];
                if (cached.len == 0) continue;
                dim.putCachedChunkPacket(work.hashes[i], cached);
                work.cached_packets[i] = &.{};
            }
        }

        for (0..work.count) |i| {
            const compressed = work.packets[i];
            if (compressed.len == 0) continue;
            player.connection.sendReliableMessage(compressed, .Normal);
            allocator.free(compressed);
        }

        for (0..work.count) |i| {
            player.sent_chunks.put(work.hashes[i], {}) catch {};
        }
    }

    t1 = std.time.nanoTimestamp();
    work.conduit.profiler.record(.batch_send, @intCast(@max(0, t1 - t0)));

    t0 = std.time.nanoTimestamp();
    if (dimension) |dim| {
        for (0..work.count) |i| {
            if (work.chunks[i] == null or !work.in_simulation[i]) continue;
            {
                applyParsedBlockData(allocator, dim, &work.block_data[i]);
            }
        }

        if (work.count > 0) {
            sendChunkBlockActorData(allocator, dim, player, work);
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
    }

    for (data.parsed_entities) |entity| {
        const pos = Protocol.BlockPosition{ .x = entity.x, .y = entity.y, .z = entity.z };
        const block = dim.getBlockPtr(pos) orelse continue;
        if (block.hasTrait(ChestTrait.ChestTrait.identifier)) {
            ChestTrait.restoreAdjacentPairing(block);
        }
    }

    for (data.parsed_entities) |entity| {
        const nbt_bytes = entity.nbt_data orelse continue;
        const pos = Protocol.BlockPosition{ .x = entity.x, .y = entity.y, .z = entity.z };
        const block = dim.getBlockPtr(pos) orelse continue;

        var stream = @import("BinaryStream").BinaryStream.init(allocator, nbt_bytes, null);
        var tag = NBT.CompoundTag.read(&stream, allocator, NBT.ReadWriteOptions.default) catch continue;
        defer tag.deinit(allocator);
        block.fireEvent(.Deserialize, .{&tag});
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

fn blockEntityTypeId(block_identifier: []const u8) []const u8 {
    if (std.mem.eql(u8, block_identifier, "minecraft:barrel")) return "Barrel";
    if (std.mem.eql(u8, block_identifier, "minecraft:chest")) return "Chest";
    if (std.mem.eql(u8, block_identifier, "minecraft:trapped_chest")) return "TrappedChest";
    return block_identifier;
}

fn sendChunkBlockActorData(allocator: std.mem.Allocator, dim: *Dimension, player: *Player, work: *const ChunkBatchWork) void {
    for (0..work.count) |i| {
        const coord = work.coords[i];
        if (work.in_simulation[i] and dim.getChunk(coord.x, coord.z) != null) {
            sendLiveBlockActorDataForChunk(allocator, player, dim, coord.x, coord.z);
            continue;
        }

        const data = work.block_data[i];
        for (data.parsed_entities) |entity| {
            const nbt_bytes = entity.nbt_data orelse continue;
            var stream = BinaryStream.init(allocator, nbt_bytes, null);
            var tag = NBT.CompoundTag.read(&stream, allocator, NBT.ReadWriteOptions.default) catch continue;
            defer tag.deinit(allocator);

            const position = Protocol.BlockPosition{
                .x = entity.x,
                .y = entity.y,
                .z = entity.z,
            };

            var s = BinaryStream.init(allocator, null, null);
            defer s.deinit();
            const pkt = Protocol.BlockActorDataPacket{
                .position = position,
                .nbt = tag,
            };
            const serialized = pkt.serialize(&s, allocator) catch continue;
            player.network.sendPacket(player.connection, serialized) catch {};
            sendTileFixAt(allocator, player, dim, position);
        }
    }
}

fn sendLiveBlockActorDataForChunk(allocator: std.mem.Allocator, player: *Player, dim: *Dimension, cx: i32, cz: i32) void {
    for (dim.getBlocksInChunk(cx, cz)) |block| {
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
        const id_value = allocator.dupe(u8, blockEntityTypeId(block.getIdentifier())) catch continue;
        tag.set("id", .{ .String = NBT.StringTag.init(id_value, null) }) catch continue;
        tag.set("x", .{ .Int = NBT.IntTag.init(block.position.x, null) }) catch continue;
        tag.set("y", .{ .Int = NBT.IntTag.init(block.position.y, null) }) catch continue;
        tag.set("z", .{ .Int = NBT.IntTag.init(block.position.z, null) }) catch continue;
        block.fireEvent(.Serialize, .{&tag});

        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        const pkt = Protocol.BlockActorDataPacket{
            .position = block.position,
            .nbt = tag,
        };
        const serialized = pkt.serialize(&stream, allocator) catch continue;
        player.network.sendPacket(player.connection, serialized) catch {};
        sendTileFixAt(allocator, player, dim, block.position);
    }
}

fn sendTileFixAt(allocator: std.mem.Allocator, player: *Player, dim: *Dimension, position: Protocol.BlockPosition) void {
    const block = dim.getBlockPtr(position) orelse return;
    const perm = block.getPermutation(0) catch return;
    const block_ids = [_]u32{ 0, @bitCast(perm.network_id) };

    for (block_ids) |network_id| {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        const packet = Protocol.UpdateBlockPacket{
            .position = position,
            .networkBlockId = network_id,
        };
        const serialized = packet.serialize(&stream) catch continue;
        player.network.sendPacket(player.connection, serialized) catch {};
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
    allocator.free(work.in_simulation);
    allocator.free(work.packets);
    for (0..work.count) |i| {
        if (work.cached_packets[i].len > 0) allocator.free(work.cached_packets[i]);
    }
    allocator.free(work.cached_packets);
    allocator.free(work.chunks);
    freeBlockDataSlice(allocator, work.block_data, work.count);
    work.arena.deinit();
    allocator.destroy(work);
}

fn serializeChunkPacket(allocator: std.mem.Allocator, chunk: *Chunk, cx: i32, cz: i32, dim_type: Protocol.DimensionType) ?[]const u8 {
    var chunk_stream = BinaryStream.init(allocator, null, null);
    defer chunk_stream.deinit();
    chunk.serialize(&chunk_stream) catch return null;

    var pkt_stream = BinaryStream.init(allocator, null, null);
    defer pkt_stream.deinit();

    var level_chunk = Protocol.LevelChunkPacket{
        .x = cx,
        .z = cz,
        .dimension = dim_type,
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
        return true;
    };

    const dimension = state.dimension;
    const sim_dist = dimension.simulation_distance;

    while (state.inflight < MAX_INFLIGHT_BATCHES and (state.upgrade_idx < state.upgrade_hashes.len or state.ring <= state.radius)) {
        if (state.upgrade_idx < state.upgrade_hashes.len) {
            const count = @min(BATCH_SIZE, state.upgrade_hashes.len - state.upgrade_idx);

            const w_coords = allocator.alloc(ChunkCoord, count) catch break;
            const w_hashes = allocator.alloc(i64, count) catch {
                allocator.free(w_coords);
                break;
            };
            const w_in_simulation = allocator.alloc(bool, count) catch {
                allocator.free(w_hashes);
                allocator.free(w_coords);
                break;
            };
            const w_packets = allocator.alloc([]const u8, count) catch {
                allocator.free(w_in_simulation);
                allocator.free(w_hashes);
                allocator.free(w_coords);
                break;
            };
            const w_cached_packets = allocator.alloc([]const u8, count) catch {
                allocator.free(w_packets);
                allocator.free(w_in_simulation);
                allocator.free(w_hashes);
                allocator.free(w_coords);
                break;
            };
            const w_chunks = allocator.alloc(?*Chunk, count) catch {
                allocator.free(w_cached_packets);
                allocator.free(w_packets);
                allocator.free(w_in_simulation);
                allocator.free(w_hashes);
                allocator.free(w_coords);
                break;
            };
            const w_block_data = allocator.alloc(ChunkBlockData, count) catch {
                allocator.free(w_chunks);
                allocator.free(w_cached_packets);
                allocator.free(w_packets);
                allocator.free(w_in_simulation);
                allocator.free(w_hashes);
                allocator.free(w_coords);
                break;
            };

            for (0..count) |i| {
                const idx = state.upgrade_idx + i;
                w_coords[i] = state.upgrade_coords[idx];
                w_hashes[i] = state.upgrade_hashes[idx];
                w_in_simulation[i] = true;
                w_packets[i] = &.{};
                w_cached_packets[i] = &.{};
                w_chunks[i] = null;
                w_block_data[i] = .{ .parsed_entities = &.{}, .trait_positions = &.{} };
            }

            const work = allocator.create(ChunkBatchWork) catch {
                allocator.free(w_block_data);
                allocator.free(w_chunks);
                allocator.free(w_cached_packets);
                allocator.free(w_packets);
                allocator.free(w_in_simulation);
                allocator.free(w_hashes);
                allocator.free(w_coords);
                break;
            };

            work.* = .{
                .coords = w_coords,
                .hashes = w_hashes,
                .in_simulation = w_in_simulation,
                .send_chunk_packets = false,
                .packets = w_packets,
                .cached_packets = w_cached_packets,
                .chunks = w_chunks,
                .block_data = w_block_data,
                .count = count,
                .runtime_id = state.runtime_id,
                .conduit = state.conduit,
                .allocator = allocator,
                .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .dimension = dimension,
                .options = player.network.options,
                .provider = dimension.world.provider,
                .dim_type = dimension.dimension_type,
                .generator = if (dimension.generator) |gen| gen.generator else null,
                .sim_distance = dimension.simulation_distance,
                .center_x = state.center_x,
                .center_z = state.center_z,
            };

            state.upgrade_idx += count;
            state.inflight += 1;

            state.conduit.threaded_tasks.enqueue(.{
                .work = workerLoadAndCompress,
                .callback = onBatchComplete,
                .cleanup = cleanupBatchWork,
                .ctx = @ptrCast(work),
            }) catch {
                cleanupBatchWork(@ptrCast(work));
            };
            continue;
        }

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
                    if (sim_dist <= 0) {
                        if (dimension.getCachedChunkPacket(chunk_hash)) |cached| {
                            player.connection.sendReliableMessage(cached, .Normal);
                            player.sent_chunks.put(chunk_hash, {}) catch {};
                            continue;
                        }
                    }
                    {
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

            const in_simulation = dx * dx + dz * dz <= sim_dist * sim_dist;
            if (!in_simulation) {
                if (dimension.getCachedChunkPacket(chunk_hash)) |cached| {
                    player.connection.sendReliableMessage(cached, .Normal);
                    player.sent_chunks.put(chunk_hash, {}) catch {};
                    continue;
                }
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
        const w_in_simulation = allocator.alloc(bool, count) catch {
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };
        const w_packets = allocator.alloc([]const u8, count) catch {
            allocator.free(w_in_simulation);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };
        const w_cached_packets = allocator.alloc([]const u8, count) catch {
            allocator.free(w_packets);
            allocator.free(w_in_simulation);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };
        const w_chunks = allocator.alloc(?*Chunk, count) catch {
            allocator.free(w_cached_packets);
            allocator.free(w_packets);
            allocator.free(w_in_simulation);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };
        const w_block_data = allocator.alloc(ChunkBlockData, count) catch {
            allocator.free(w_chunks);
            allocator.free(w_cached_packets);
            allocator.free(w_packets);
            allocator.free(w_in_simulation);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };

        for (0..count) |i| {
            w_coords[i] = coord_buf[i];
            w_hashes[i] = hash_buf[i];
            const dx = w_coords[i].x - state.center_x;
            const dz = w_coords[i].z - state.center_z;
            w_in_simulation[i] = dx * dx + dz * dz <= sim_dist * sim_dist;
            w_chunks[i] = null;
            w_packets[i] = &.{};
            w_cached_packets[i] = &.{};
            w_block_data[i] = .{ .parsed_entities = &.{}, .trait_positions = &.{} };
            player.sent_chunks.put(w_hashes[i], {}) catch {};
        }

        const work = allocator.create(ChunkBatchWork) catch {
            allocator.free(w_block_data);
            allocator.free(w_chunks);
            allocator.free(w_cached_packets);
            allocator.free(w_packets);
            allocator.free(w_in_simulation);
            allocator.free(w_hashes);
            allocator.free(w_coords);
            break;
        };

        work.* = .{
            .coords = w_coords,
            .hashes = w_hashes,
            .in_simulation = w_in_simulation,
            .send_chunk_packets = true,
            .packets = w_packets,
            .cached_packets = w_cached_packets,
            .chunks = w_chunks,
            .block_data = w_block_data,
            .count = count,
            .runtime_id = state.runtime_id,
            .conduit = state.conduit,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .dimension = dimension,
            .options = player.network.options,
            .provider = dimension.world.provider,
            .dim_type = dimension.dimension_type,
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

    if (state.upgrade_idx >= state.upgrade_hashes.len and state.ring > state.radius) {
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

test "render-only pure terrain chunks stay cacheable" {
    const data = ChunkBlockData{ .parsed_entities = &.{}, .trait_positions = &.{} };
    try std.testing.expect(shouldCacheChunkPacket(false, &data));
}

test "render-only chunks with block actors bypass packet cache" {
    const entity = ParsedBlockEntity{
        .x = 0,
        .y = 64,
        .z = 0,
        .trait_ids = &.{},
        .nbt_data = null,
    };
    const parsed = [_]ParsedBlockEntity{entity};
    const data = ChunkBlockData{ .parsed_entities = &parsed, .trait_positions = &.{} };
    try std.testing.expect(!shouldCacheChunkPacket(false, &data));
}

test "render-only chunks skip trait-position scan" {
    try std.testing.expect(!shouldReadTraitPositions(false));
    try std.testing.expect(shouldReadTraitPositions(true));
}

test "chunk column packet serialization matches full chunk path" {
    const allocator = std.testing.allocator;

    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();
    try BlockType.initRegistry(allocator);
    defer BlockType.deinitRegistry();

    const air_type = try BlockType.init(allocator, "minecraft:air");
    try air_type.register();
    const air_state = BlockState.init(allocator);
    const air_perm = try BlockPermutation.init(allocator, 0, "minecraft:air", air_state);
    try air_perm.register();
    try air_type.addPermutation(air_perm);

    const stone_type = try BlockType.init(allocator, "minecraft:stone");
    try stone_type.register();
    const stone_state = BlockState.init(allocator);
    const stone_perm = try BlockPermutation.init(allocator, 1, "minecraft:stone", stone_state);
    try stone_perm.register();
    try stone_type.addPermutation(stone_perm);

    var chunk = Chunk.init(allocator, 0, 0, .Overworld);
    defer chunk.deinit();
    try chunk.setPermutation(1, 64, 1, stone_perm, 0);
    try chunk.setPermutation(2, 65, 2, stone_perm, 0);

    var column = ChunkColumnData{};
    column.has_version = true;
    defer column.deinit(allocator);

    for (chunk.subchunks, 0..) |maybe_sc, i| {
        const sc = maybe_sc orelse continue;
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        try sc.serializePersistence(&stream, allocator);
        column.subchunks[i] = try allocator.dupe(u8, stream.getBuffer());
    }

    const full_packet = serializeChunkPacket(allocator, &chunk, 0, 0, .Overworld) orelse return error.TestUnexpectedResult;
    defer allocator.free(full_packet);

    const column_packet = serializeChunkPacketFromColumn(allocator, &column, 0, 0, .Overworld) orelse return error.TestUnexpectedResult;
    defer allocator.free(column_packet);

    try std.testing.expectEqualSlices(u8, full_packet, column_packet);
}

test "parse block entity blob decodes positions and traits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tag = NBT.CompoundTag.init(allocator, null);
    try tag.set("x", .{ .Int = NBT.IntTag.init(12, null) });
    try tag.set("y", .{ .Int = NBT.IntTag.init(64, null) });
    try tag.set("z", .{ .Int = NBT.IntTag.init(-4, null) });
    try tag.set("id", .{ .String = NBT.StringTag.init(try allocator.dupe(u8, "Chest"), null) });

    const trait_items = try allocator.alloc(NBT.Tag, 1);
    trait_items[0] = .{ .String = NBT.StringTag.init(try allocator.dupe(u8, "test:trait"), null) };
    try tag.set("traits", .{ .List = NBT.ListTag.init(trait_items, null) });

    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();
    try NBT.CompoundTag.write(&stream, &tag, NBT.ReadWriteOptions.default);

    const parsed = parseBlockEntitiesFromBytes(allocator, stream.getBuffer());
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqual(@as(i32, 12), parsed[0].x);
    try std.testing.expectEqual(@as(i32, 64), parsed[0].y);
    try std.testing.expectEqual(@as(i32, -4), parsed[0].z);
    try std.testing.expectEqual(@as(usize, 1), parsed[0].trait_ids.len);
    try std.testing.expectEqualStrings("test:trait", parsed[0].trait_ids[0]);
}
