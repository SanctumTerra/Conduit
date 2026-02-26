const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const Conduit = @import("../../conduit.zig").Conduit;
const Task = @import("../../tasks.zig").Task;

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

const ChunkStreamState = struct {
    conduit: *Conduit,
    runtime_id: i64,
    allocator: std.mem.Allocator,
    center_x: i32,
    center_z: i32,
    radius: i32,
    ring: i32,
    ring_idx: i32,
};

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

    var did_load = false;

    while (state.ring <= state.radius) {
        const ring = state.ring;
        if (ring == 0) {
            state.ring = 1;
            state.ring_idx = 0;
            const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = state.center_x, .z = state.center_z });
            if (!player.sent_chunks.contains(chunk_hash)) {
                const cached = dimension.getChunk(state.center_x, state.center_z) != null;
                if (!cached and did_load) return false;
                sendAndFlush(dimension, state.center_x, state.center_z, allocator, player);
                if (!cached) did_load = true;
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

        const cached = dimension.getChunk(coords[0], coords[1]) != null;
        if (!cached and did_load) return false;
        sendAndFlush(dimension, coords[0], coords[1], allocator, player);
        if (!cached) did_load = true;
    }

    allocator.destroy(state);
    return true;
}

fn sendAndFlush(dimension: *Dimension, cx: i32, cz: i32, allocator: std.mem.Allocator, player: *Player) void {
    const chunk = dimension.getOrCreateChunk(cx, cz) catch return;

    var chunk_stream = BinaryStream.init(allocator, null, null);
    defer chunk_stream.deinit();
    chunk.serialize(&chunk_stream) catch return;

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

    const serialized = level_chunk.serialize(&pkt_stream) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};
    player.sent_chunks.put(Protocol.ChunkCoords.hash(.{ .x = cx, .z = cz }), {}) catch {};
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
