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
    player.onSpawn();

    const snapshots = network.conduit.getPlayerSnapshots();

    var all_entries = std.ArrayList(Protocol.PlayerListEntry){ .items = &.{}, .capacity = 0 };
    defer all_entries.deinit(network.allocator);

    for (snapshots) |p| {
        try all_entries.append(network.allocator, .{
            .uuid = p.uuid,
            .entityUniqueId = p.runtimeId,
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
        .entityUniqueId = player.runtimeId,
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
        if (other.runtimeId == player.runtimeId) continue;

        try network.sendPacket(other.connection, new_serialized);

        var add_stream = BinaryStream.init(network.allocator, null, null);
        defer add_stream.deinit();
        const add_packet = Protocol.AddPlayerPacket{
            .uuid = player.uuid,
            .username = player.username,
            .entityRuntimeId = player.runtimeId,
            .position = player.position,
            .entityProperties = Protocol.PropertySyncData.init(network.allocator),
            .abilityEntityUniqueId = player.runtimeId,
        };
        const add_serialized = try add_packet.serialize(&add_stream);
        try network.sendPacket(other.connection, add_serialized);

        var skin_new_stream = BinaryStream.init(network.allocator, null, null);
        defer skin_new_stream.deinit();
        const skin_new_packet = Protocol.PlayerSkinPacket{
            .uuid = player.uuid,
            .skin = &player.loginData.client_data,
        };
        const skin_new_serialized = try skin_new_packet.serialize(&skin_new_stream, network.allocator);
        try network.sendPacket(other.connection, skin_new_serialized);

        var other_stream = BinaryStream.init(network.allocator, null, null);
        defer other_stream.deinit();
        const other_packet = Protocol.AddPlayerPacket{
            .uuid = other.uuid,
            .username = other.username,
            .entityRuntimeId = other.runtimeId,
            .position = other.position,
            .entityProperties = Protocol.PropertySyncData.init(network.allocator),
            .abilityEntityUniqueId = other.runtimeId,
        };
        const other_serialized = try other_packet.serialize(&other_stream);
        try network.sendPacket(connection, other_serialized);

        var skin_other_stream = BinaryStream.init(network.allocator, null, null);
        defer skin_other_stream.deinit();
        const skin_other_packet = Protocol.PlayerSkinPacket{
            .uuid = other.uuid,
            .skin = &other.loginData.client_data,
        };
        const skin_other_serialized = try skin_other_packet.serialize(&skin_other_stream, network.allocator);
        try network.sendPacket(connection, skin_other_serialized);

        var other_flags_stream = BinaryStream.init(network.allocator, null, null);
        defer other_flags_stream.deinit();
        const other_flags_data = try other.flags.buildDataItems(network.allocator);
        var other_flags_packet = Protocol.SetActorDataPacket.init(network.allocator, other.runtimeId, 0, other_flags_data);
        defer other_flags_packet.deinit();
        const other_flags_serialized = try other_flags_packet.serialize(&other_flags_stream);
        try network.sendPacket(connection, other_flags_serialized);

        var new_flags_stream = BinaryStream.init(network.allocator, null, null);
        defer new_flags_stream.deinit();
        const new_flags_data = try player.flags.buildDataItems(network.allocator);
        var new_flags_packet = Protocol.SetActorDataPacket.init(network.allocator, player.runtimeId, 0, new_flags_data);
        defer new_flags_packet.deinit();
        const new_flags_serialized = try new_flags_packet.serialize(&new_flags_stream);
        try network.sendPacket(other.connection, new_flags_serialized);
    }
}
