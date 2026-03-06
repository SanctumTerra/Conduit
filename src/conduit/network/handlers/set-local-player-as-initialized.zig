const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

const Player = @import("../../player/player.zig").Player;

pub fn handleSetLocalPlayerAsInitialized(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    _: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    if (player.spawned) return;
    player.spawned = true;

    try player.onSpawn();

    const snapshots = network.conduit.getPlayerSnapshots();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    for (snapshots) |p| {
        const temp_allocator = arena.allocator();

        const entry = [_]Protocol.PlayerListEntry{.{
            .uuid = p.uuid,
            .entityUniqueId = p.entity.runtime_id,
            .username = p.username,
            .xuid = p.xuid,
            .skin = &p.loginData.client_data,
            .buildPlatform = @intCast(p.loginData.client_data.device_os),
        }};

        var stream = BinaryStream.init(temp_allocator, null, null);
        defer stream.deinit();
        var packet = Protocol.PlayerListPacket{
            .action = .Add,
            .entries = &entry,
        };
        const serialized = try packet.serialize(&stream, temp_allocator);
        try network.sendPacket(connection, serialized);

        _ = arena.reset(.retain_capacity);
    }

    const new_entry = [_]Protocol.PlayerListEntry{.{
        .uuid = player.uuid,
        .entityUniqueId = player.entity.runtime_id,
        .username = player.username,
        .xuid = player.xuid,
        .skin = &player.loginData.client_data,
        .buildPlatform = @intCast(player.loginData.client_data.device_os),
    }};

    const temp_allocator = arena.allocator();
    var new_stream = BinaryStream.init(temp_allocator, null, null);
    defer new_stream.deinit();
    var new_packet = Protocol.PlayerListPacket{
        .action = .Add,
        .entries = &new_entry,
    };
    const new_serialized = try new_packet.serialize(&new_stream, temp_allocator);

    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        try network.sendPacket(other.connection, new_serialized);
    }
}
