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

    var all_entries = std.ArrayList(Protocol.PlayerListEntry){ .items = &.{}, .capacity = 0 };
    defer all_entries.deinit(network.allocator);

    for (snapshots) |p| {
        try all_entries.append(network.allocator, .{
            .uuid = p.uuid,
            .entityUniqueId = p.entity.runtime_id,
            .username = p.username,
            .xuid = p.xuid,
            .skin = &p.loginData.client_data,
            .buildPlatform = @intCast(p.loginData.client_data.device_os),
        });
    }

    var full_stream = BinaryStream.init(network.allocator, null, null);
    defer full_stream.deinit();
    var full_packet = Protocol.PlayerListPacket{
        .action = .Add,
        .entries = all_entries.items,
    };
    const full_serialized = try full_packet.serialize(&full_stream, network.allocator);
    try network.sendPacket(connection, full_serialized);

    const new_entry = [_]Protocol.PlayerListEntry{.{
        .uuid = player.uuid,
        .entityUniqueId = player.entity.runtime_id,
        .username = player.username,
        .xuid = player.xuid,
        .skin = &player.loginData.client_data,
        .buildPlatform = @intCast(player.loginData.client_data.device_os),
    }};

    var new_stream = BinaryStream.init(network.allocator, null, null);
    defer new_stream.deinit();
    var new_packet = Protocol.PlayerListPacket{
        .action = .Add,
        .entries = &new_entry,
    };
    const new_serialized = try new_packet.serialize(&new_stream, network.allocator);

    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        try network.sendPacket(other.connection, new_serialized);
    }
}
