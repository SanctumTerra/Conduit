const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const Conduit = @import("../../conduit.zig").Conduit;
const Chunk = @import("../../world/chunk/chunk.zig").Chunk;
const Raknet = @import("Raknet");
const ThreadedTask = @import("../../tasks/threaded-tasks.zig").ThreadedTask;
const Compression = @import("../../network/compression/compression.zig").Compression;
const CompressionOptions = @import("../../network/compression/options.zig").CompressionOptions;
const WorldProvider = @import("../../world/provider/world-provider.zig").WorldProvider;

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

const BATCH_SIZE: usize = 16;
const MAX_INFLIGHT_BATCHES: u32 = 2;

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

const ChunkBatchWork = struct {
    cached_packets: [][]const u8,
    cached_hashes: []i64,
    cached_count: usize,
    uncached_coords: []ChunkCoord,
    uncached_hashes: []i64,
    uncached_packets: [][]const u8,
    uncached_chunks: []?*Chunk,
    uncached_count: usize,
    runtime_id: i64,
    conduit: *Conduit,
    allocator: std.mem.Allocator,
    options: CompressionOptions,
    provider: WorldProvider,
    dim_type: Protocol.DimensionType,
    generator: ?@import("../../world/generator/terrain-generator.zig").TerrainGenerator,
    sim_distance: i32,
};

fn workerLoadAndCompress(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;

    for (0..work.cached_count) |i| {
        const pkt = work.cached_packets[i];
        if (pkt.len == 0) continue;
        const packets = [_][]const u8{pkt};
        const compressed = Compression.compress(&packets, work.options, allocator) catch {
            continue;
        };
        allocator.free(pkt);
        work.cached_packets[i] = compressed;
    }

    for (0..work.uncached_count) |i| {
        const coord = work.uncached_coords[i];
        const chunk = work.provider.readChunkDirect(coord.x, coord.z, work.dim_type) catch blk: {
            if (work.generator) |gen| {
                break :blk gen.generate(allocator, coord.x, coord.z) catch {
                    work.uncached_packets[i] = &.{};
                    work.uncached_chunks[i] = null;
                    continue;
                };
            } else {
                work.uncached_packets[i] = &.{};
                work.uncached_chunks[i] = null;
                continue;
            }
        };

        work.uncached_chunks[i] = chunk;

        const pkt = serializeChunkPacket(allocator, chunk, coord.x, coord.z) orelse {
            work.uncached_packets[i] = &.{};
            continue;
        };

        const packets = [_][]const u8{pkt};
        work.uncached_packets[i] = Compression.compress(&packets, work.options, allocator) catch {
            allocator.free(pkt);
            work.uncached_packets[i] = &.{};
            continue;
        };
        allocator.free(pkt);
    }
}

fn onBatchComplete(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;
    defer {
        decrementInflight(work.conduit, work.runtime_id);
        allocator.free(work.cached_packets);
        allocator.free(work.cached_hashes);
        allocator.free(work.uncached_coords);
        allocator.free(work.uncached_hashes);
        allocator.free(work.uncached_packets);
        allocator.free(work.uncached_chunks);
        allocator.destroy(work);
    }

    const player = work.conduit.players.get(work.runtime_id) orelse {
        for (work.cached_packets[0..work.cached_count]) |pkt| {
            if (pkt.len > 0) allocator.free(pkt);
        }
        for (0..work.uncached_count) |i| {
            if (work.uncached_packets[i].len > 0) allocator.free(work.uncached_packets[i]);
            if (work.uncached_chunks[i]) |chunk| {
                var c = chunk;
                c.deinit();
                allocator.destroy(c);
            }
        }
        return;
    };

    for (work.cached_packets[0..work.cached_count], work.cached_hashes[0..work.cached_count]) |compressed, hash| {
        if (compressed.len == 0) continue;
        player.connection.sendReliableMessage(compressed, .Normal);
        allocator.free(compressed);
        player.sent_chunks.put(hash, {}) catch {};
    }

    const world = work.conduit.getWorld("world");
    const dimension = if (world) |w| w.getDimension("overworld") else null;

    for (0..work.uncached_count) |i| {
        if (work.uncached_chunks[i]) |chunk| {
            if (dimension) |dim| {
                if (isInSimulationRange(work.conduit, chunk.x, chunk.z, work.sim_distance)) {
                    const hash = @import("../../world/dimension/dimension.zig").chunkHash(chunk.x, chunk.z);
                    const result = dim.chunks.fetchPut(hash, chunk) catch {
                        var c = chunk;
                        c.deinit();
                        allocator.destroy(c);
                        work.uncached_chunks[i] = null;
                        continue;
                    };
                    if (result) |old| {
                        dim.world.provider.uncacheChunk(chunk.x, chunk.z, dim);
                        var old_chunk = old.value;
                        old_chunk.deinit();
                        allocator.destroy(old_chunk);
                    }
                    dim.world.provider.readBlockEntities(chunk, dim) catch {};
                } else {
                    var c = chunk;
                    c.deinit();
                    allocator.destroy(c);
                }
            } else {
                var c = chunk;
                c.deinit();
                allocator.destroy(c);
            }
        }
        const compressed = work.uncached_packets[i];
        if (compressed.len == 0) continue;
        player.connection.sendReliableMessage(compressed, .Normal);
        allocator.free(compressed);
        player.sent_chunks.put(work.uncached_hashes[i], {}) catch {};
    }
}

fn cleanupBatchWork(ctx: *anyopaque) void {
    const work: *ChunkBatchWork = @ptrCast(@alignCast(ctx));
    const allocator = work.allocator;
    decrementInflight(work.conduit, work.runtime_id);
    for (work.cached_packets[0..work.cached_count]) |pkt| {
        if (pkt.len > 0) allocator.free(pkt);
    }
    for (0..work.uncached_count) |i| {
        if (work.uncached_packets[i].len > 0) allocator.free(work.uncached_packets[i]);
        if (work.uncached_chunks[i]) |chunk| {
            var c = chunk;
            c.deinit();
            allocator.destroy(c);
        }
    }
    allocator.free(work.cached_packets);
    allocator.free(work.cached_hashes);
    allocator.free(work.uncached_coords);
    allocator.free(work.uncached_hashes);
    allocator.free(work.uncached_packets);
    allocator.free(work.uncached_chunks);
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

fn isInSimulationRange(conduit: *Conduit, cx: i32, cz: i32, sim_distance: i32) bool {
    const snapshots = conduit.getPlayerSnapshots();
    for (snapshots) |p| {
        if (!p.spawned) continue;
        const pcx = @as(i32, @intFromFloat(@floor(p.entity.position.x))) >> 4;
        const pcz = @as(i32, @intFromFloat(@floor(p.entity.position.z))) >> 4;
        const dx = cx - pcx;
        const dz = cz - pcz;
        if (dx * dx + dz * dz <= sim_distance * sim_distance) return true;
    }
    return false;
}

fn chunkStreamStep(ctx: *anyopaque) bool {
    const state: *ChunkStreamState = @ptrCast(@alignCast(ctx));
    const allocator = state.allocator;

    const player = state.conduit.players.get(state.runtime_id) orelse {
        allocator.destroy(state);
        return true;
    };

    if (state.inflight >= MAX_INFLIGHT_BATCHES) return false;

    const world = state.conduit.getWorld("world") orelse {
        allocator.destroy(state);
        return true;
    };
    const dimension = world.getDimension("overworld") orelse {
        allocator.destroy(state);
        return true;
    };

    var cached_pkt_buf: [BATCH_SIZE][]const u8 = undefined;
    var cached_hash_buf: [BATCH_SIZE]i64 = undefined;
    var cached_count: usize = 0;

    var uncached_coord_buf: [BATCH_SIZE]ChunkCoord = undefined;
    var uncached_hash_buf: [BATCH_SIZE]i64 = undefined;
    var uncached_count: usize = 0;

    var total_count: usize = 0;

    while (state.ring <= state.radius and total_count < BATCH_SIZE) {
        const ring = state.ring;
        if (ring == 0) {
            state.ring = 1;
            state.ring_idx = 0;
            const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = state.center_x, .z = state.center_z });
            if (!player.sent_chunks.contains(chunk_hash)) {
                collectChunk(dimension, state.center_x, state.center_z, chunk_hash, allocator, &cached_pkt_buf, &cached_hash_buf, &cached_count, &uncached_coord_buf, &uncached_hash_buf, &uncached_count);
                total_count += 1;
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

        collectChunk(dimension, coords[0], coords[1], chunk_hash, allocator, &cached_pkt_buf, &cached_hash_buf, &cached_count, &uncached_coord_buf, &uncached_hash_buf, &uncached_count);
        total_count += 1;
    }

    if (cached_count > 0 or uncached_count > 0) {
        submitBatch(state, player, allocator, world, dimension, &cached_pkt_buf, &cached_hash_buf, cached_count, &uncached_coord_buf, &uncached_hash_buf, uncached_count);
    }

    if (state.ring > state.radius) {
        allocator.destroy(state);
        return true;
    }
    return false;
}

fn collectChunk(
    dimension: *Dimension,
    cx: i32,
    cz: i32,
    chunk_hash: i64,
    allocator: std.mem.Allocator,
    cached_pkt_buf: *[BATCH_SIZE][]const u8,
    cached_hash_buf: *[BATCH_SIZE]i64,
    cached_count: *usize,
    uncached_coord_buf: *[BATCH_SIZE]ChunkCoord,
    uncached_hash_buf: *[BATCH_SIZE]i64,
    uncached_count: *usize,
) void {
    if (dimension.getChunk(cx, cz)) |chunk| {
        if (serializeChunkPacket(allocator, chunk, cx, cz)) |pkt| {
            cached_pkt_buf[cached_count.*] = pkt;
            cached_hash_buf[cached_count.*] = chunk_hash;
            cached_count.* += 1;
        }
    } else {
        uncached_coord_buf[uncached_count.*] = .{ .x = cx, .z = cz };
        uncached_hash_buf[uncached_count.*] = chunk_hash;
        uncached_count.* += 1;
    }
}

fn submitBatch(
    state: *ChunkStreamState,
    player: *Player,
    allocator: std.mem.Allocator,
    world: *@import("../../world/world.zig").World,
    dimension: *Dimension,
    cached_pkt_buf: *[BATCH_SIZE][]const u8,
    cached_hash_buf: *[BATCH_SIZE]i64,
    cached_count: usize,
    uncached_coord_buf: *[BATCH_SIZE]ChunkCoord,
    uncached_hash_buf: *[BATCH_SIZE]i64,
    uncached_count: usize,
) void {
    const work = allocator.create(ChunkBatchWork) catch return;

    const cp = allocator.alloc([]const u8, cached_count) catch {
        allocator.destroy(work);
        return;
    };
    const ch = allocator.alloc(i64, cached_count) catch {
        allocator.free(cp);
        allocator.destroy(work);
        return;
    };
    const uc = allocator.alloc(ChunkCoord, uncached_count) catch {
        allocator.free(ch);
        allocator.free(cp);
        allocator.destroy(work);
        return;
    };
    const uh = allocator.alloc(i64, uncached_count) catch {
        allocator.free(uc);
        allocator.free(ch);
        allocator.free(cp);
        allocator.destroy(work);
        return;
    };
    const up = allocator.alloc([]const u8, uncached_count) catch {
        allocator.free(uh);
        allocator.free(uc);
        allocator.free(ch);
        allocator.free(cp);
        allocator.destroy(work);
        return;
    };
    const uchunks = allocator.alloc(?*Chunk, uncached_count) catch {
        allocator.free(up);
        allocator.free(uh);
        allocator.free(uc);
        allocator.free(ch);
        allocator.free(cp);
        allocator.destroy(work);
        return;
    };

    for (0..cached_count) |i| {
        cp[i] = cached_pkt_buf[i];
        ch[i] = cached_hash_buf[i];
        player.sent_chunks.put(ch[i], {}) catch {};
    }
    for (0..uncached_count) |i| {
        uc[i] = uncached_coord_buf[i];
        uh[i] = uncached_hash_buf[i];
        up[i] = &.{};
        uchunks[i] = null;
        player.sent_chunks.put(uh[i], {}) catch {};
    }

    work.* = .{
        .cached_packets = cp,
        .cached_hashes = ch,
        .cached_count = cached_count,
        .uncached_coords = uc,
        .uncached_hashes = uh,
        .uncached_packets = up,
        .uncached_chunks = uchunks,
        .uncached_count = uncached_count,
        .runtime_id = state.runtime_id,
        .conduit = state.conduit,
        .allocator = allocator,
        .options = player.network.options,
        .provider = world.provider,
        .dim_type = .Overworld,
        .generator = if (dimension.generator) |gen| gen.generator else null,
        .sim_distance = dimension.simulation_distance,
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
