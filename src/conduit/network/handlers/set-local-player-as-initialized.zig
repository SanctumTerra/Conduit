const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Compression = @import("../compression/compression.zig").Compression;

const Player = @import("../../player/player.zig").Player;

const PlayerInitStage = enum(u8) {
    on_spawn,
    send_existing_players,
    broadcast_new_player,
};

const PlayerInitTask = struct {
    network: *NetworkHandler,
    player: *Player,
    stage: PlayerInitStage = .on_spawn,
    existing_idx: usize = 0,
};

const PLAYER_LIST_BATCH_SIZE: usize = 1;

pub fn handleSetLocalPlayerAsInitialized(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    _: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    if (player.spawned) return;

    try queuePlayerInit(network, player);
}

fn queuePlayerInit(network: *NetworkHandler, player: *Player) !void {
    network.conduit.tasks.cancelByOwner("player_init", player.entity.runtime_id, null);

    const state = try network.allocator.create(PlayerInitTask);
    errdefer network.allocator.destroy(state);
    state.* = .{
        .network = network,
        .player = player,
    };

    try network.conduit.tasks.enqueue(.{
        .func = runPlayerInitTask,
        .ctx = @ptrCast(state),
        .name = "player_init",
        .owner_id = player.entity.runtime_id,
        .cleanup = destroyPlayerInitTask,
    });
}

fn runPlayerInitTask(ctx: *anyopaque) bool {
    const state: *PlayerInitTask = @ptrCast(@alignCast(ctx));
    return runPlayerInitTaskImpl(state) catch |err| {
        Raknet.Logger.ERROR("Player init failed for {s} at stage {s}: {any}", .{
            state.player.username,
            @tagName(state.stage),
            err,
        });
        return true;
    };
}

fn runPlayerInitTaskImpl(state: *PlayerInitTask) !bool {
    const player = state.player;
    if (!player.connection.active or state.network.conduit.getPlayerByConnection(player.connection) == null) {
        return true;
    }

    switch (state.stage) {
        .on_spawn => {
            try player.onSpawn();
            state.stage = .send_existing_players;
            return false;
        },
        .send_existing_players => {
            try sendExistingPlayers(state);
            state.stage = .broadcast_new_player;
            return false;
        },
        .broadcast_new_player => {
            try broadcastNewPlayer(state);
            player.spawned = true;
            return true;
        },
    }
}

fn destroyPlayerInitTask(ctx: *anyopaque) void {
    const state: *PlayerInitTask = @ptrCast(@alignCast(ctx));
    state.network.allocator.destroy(state);
}

fn sendExistingPlayers(state: *PlayerInitTask) !void {
    const snapshots = state.network.conduit.getPlayerSnapshots();
    while (state.existing_idx < snapshots.len) {
        const candidate = snapshots[state.existing_idx];
        if (candidate.entity.runtime_id != state.player.entity.runtime_id and candidate.spawned) break;
        state.existing_idx += 1;
    }
    if (state.existing_idx >= snapshots.len) return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    const count = @min(PLAYER_LIST_BATCH_SIZE, snapshots.len - state.existing_idx);
    const entries = try temp_allocator.alloc(Protocol.PlayerListEntry, count);
    var written: usize = 0;
    var idx = state.existing_idx;
    while (idx < snapshots.len and written < count) : (idx += 1) {
        const p = snapshots[idx];
        if (p.entity.runtime_id == state.player.entity.runtime_id or !p.spawned) continue;
        entries[written] = .{
            .uuid = p.uuid,
            .entityUniqueId = p.entity.runtime_id,
            .username = p.username,
            .xuid = p.xuid,
            .skin = &p.loginData.client_data,
            .buildPlatform = @intCast(p.loginData.client_data.device_os),
        };
        written += 1;
    }
    state.existing_idx = idx;
    if (written == 0) return;

    var stream = BinaryStream.init(temp_allocator, null, null);
    defer stream.deinit();
    var packet = Protocol.PlayerListPacket{
        .action = .Add,
        .entries = entries[0..written],
    };
    const serialized = try packet.serialize(&stream, temp_allocator);
    try state.network.sendPacket(state.player.connection, serialized);
}

fn broadcastNewPlayer(state: *PlayerInitTask) !void {
    const snapshots = state.network.conduit.getPlayerSnapshots();
    if (snapshots.len <= 1) return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    const entry = [_]Protocol.PlayerListEntry{.{
        .uuid = state.player.uuid,
        .entityUniqueId = state.player.entity.runtime_id,
        .username = state.player.username,
        .xuid = state.player.xuid,
        .skin = &state.player.loginData.client_data,
        .buildPlatform = @intCast(state.player.loginData.client_data.device_os),
    }};

    var stream = BinaryStream.init(temp_allocator, null, null);
    defer stream.deinit();
    var packet = Protocol.PlayerListPacket{
        .action = .Add,
        .entries = &entry,
    };
    const serialized = try packet.serialize(&stream, temp_allocator);

    const packets = [_][]const u8{serialized};
    const compressed = try Compression.compress(&packets, state.network.options, state.network.allocator);
    defer state.network.allocator.free(compressed);

    for (snapshots) |other| {
        if (other.entity.runtime_id == state.player.entity.runtime_id) continue;
        if (!other.spawned) continue;
        other.connection.sendReliableMessage(compressed, .Normal);
    }
}
