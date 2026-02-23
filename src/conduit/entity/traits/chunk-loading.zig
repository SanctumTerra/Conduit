const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
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
    player: *Player,
    dimension: *Dimension,
    center_x: i32,
    center_z: i32,
    radius: i32,
    cx: i32,
    cz: i32,
    old_hashes: ?std.ArrayList(i64),
};

fn queueChunkStreaming(player: *Player) !void {
    const world = player.network.conduit.getWorld("world") orelse return;
    const overworld = world.getDimension("overworld") orelse return;
    const allocator = player.entity.allocator;

    const center_x = @as(i32, @intFromFloat(@floor(player.entity.position.x))) >> 4;
    const center_z = @as(i32, @intFromFloat(@floor(player.entity.position.z))) >> 4;
    const radius = player.view_distance;

    var old_hashes = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
    var it = player.sent_chunks.keyIterator();
    while (it.next()) |key| {
        const coords = Protocol.ChunkCoords.unhash(key.*);
        const dx = coords.x - center_x;
        const dz = coords.z - center_z;
        if (dx * dx + dz * dz > radius * radius) {
            old_hashes.append(allocator, key.*) catch {};
        }
    }

    for (old_hashes.items) |h| {
        _ = player.sent_chunks.remove(h);
    }
    old_hashes.deinit(allocator);

    const state = try allocator.create(ChunkStreamState);
    state.* = .{
        .player = player,
        .dimension = overworld,
        .center_x = center_x,
        .center_z = center_z,
        .radius = radius,
        .cx = center_x - radius,
        .cz = center_z - radius,
        .old_hashes = null,
    };

    try player.network.conduit.tasks.enqueue(.{
        .func = chunkStreamStep,
        .ctx = @ptrCast(state),
        .name = "chunk_streaming",
    });
}

fn chunkStreamStep(ctx: *anyopaque) bool {
    const state: *ChunkStreamState = @ptrCast(@alignCast(ctx));
    const player = state.player;
    const allocator = player.entity.allocator;
    const batch: u32 = 8;
    var sent: u32 = 0;

    var packet_batch = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer {
        for (packet_batch.items) |pkt| allocator.free(pkt);
        packet_batch.deinit(allocator);
    }

    while (sent < batch and state.cx <= state.center_x + state.radius) {
        const dx = state.cx - state.center_x;
        const dz = state.cz - state.center_z;
        if (dx * dx + dz * dz > state.radius * state.radius) {
            advance(state);
            continue;
        }

        const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = state.cx, .z = state.cz });
        if (player.sent_chunks.contains(chunk_hash)) {
            advance(state);
            continue;
        }

        const chunk = state.dimension.getOrCreateChunk(state.cx, state.cz) catch {
            advance(state);
            continue;
        };

        var chunk_stream = BinaryStream.init(allocator, null, null);
        defer chunk_stream.deinit();
        chunk.serialize(&chunk_stream) catch {
            advance(state);
            continue;
        };

        var pkt_stream = BinaryStream.init(allocator, null, null);
        defer pkt_stream.deinit();

        var level_chunk = Protocol.LevelChunkPacket{
            .x = state.cx,
            .z = state.cz,
            .dimension = .Overworld,
            .highestSubChunkCount = 0,
            .subChunkCount = @intCast(chunk.getSubChunkSendCount()),
            .cacheEnabled = false,
            .blobs = &[_]u64{},
            .data = chunk_stream.getBuffer(),
        };

        const serialized = level_chunk.serialize(&pkt_stream) catch {
            advance(state);
            continue;
        };

        packet_batch.append(allocator, allocator.dupe(u8, serialized) catch {
            advance(state);
            continue;
        }) catch {
            advance(state);
            continue;
        };

        player.sent_chunks.put(chunk_hash, {}) catch {};
        sent += 1;
        advance(state);
    }

    if (packet_batch.items.len > 0) {
        player.network.sendPackets(player.connection, packet_batch.items) catch {};
    }

    if (state.cx > state.center_x + state.radius) {
        allocator.destroy(state);
        return true;
    }
    return false;
}

fn advance(state: *ChunkStreamState) void {
    state.cz += 1;
    if (state.cz > state.center_z + state.radius) {
        state.cz = state.center_z - state.radius;
        state.cx += 1;
    }
}

pub const ChunkLoadingTrait = EntityTrait(State, .{
    .identifier = "chunk_loading",
    .onTick = onTick,
});
