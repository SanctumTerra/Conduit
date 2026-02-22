const Raknet = @import("Raknet");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const Player = @import("../../player/player.zig").Player;
const Events = @import("../../events/root.zig");

pub fn handleLogin(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    // TODO Offline mode

    const login = try Protocol.LoginPacket.deserialize(stream);
    if (login.protocol != Protocol.PROTOCOL) {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        var reason: Protocol.DisconnectReason = .OutdatedClient;
        if (login.protocol > Protocol.PROTOCOL) reason = .OutdatedServer;

        var disconnect = Protocol.DisconnectPacket{
            .hideScreen = true,
            .reason = reason,
        };
        const serialized = try disconnect.serialize(&str);
        try network.sendPacket(connection, serialized);
        return;
    }

    const player_count = network.conduit.players.count();
    if (player_count >= network.conduit.config.max_players) {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();
        var disconnect = Protocol.DisconnectPacket{
            .hideScreen = true,
            .reason = .ServerFull,
        };
        const serialized = try disconnect.serialize(&str);
        try network.sendPacket(connection, serialized);
        return;
    }

    var data = try Protocol.Login.Decoder.decodeLoginChain(network.allocator, login.identity, login.client);
    errdefer {
        data.deinit();

        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();
        var status = Protocol.PlayStatusPacket{
            .status = .FailedClient,
        };
        if (status.serialize(&str)) |ser| {
            network.sendPacket(connection, ser) catch {};
        } else |_| {}
    }

    {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();
        var status = Protocol.PlayStatusPacket{
            .status = .LoginSuccess,
        };
        if (status.serialize(&str)) |serialized| {
            network.sendPacket(connection, serialized) catch {};
        } else |_| {}
    }

    network.lastRuntimeId += 1;

    const player = try network.allocator.create(Player);
    player.* = try Player.init(
        network.allocator,
        connection,
        network,
        data,
        network.lastRuntimeId,
    );

    var event = Events.types.PlayerJoinEvent{
        .player = player,
    };
    if (!network.conduit.events.emit(.PlayerJoin, &event)) {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();
        var disconnect = Protocol.DisconnectPacket{
            .hideScreen = true,
            .reason = .Disconnected,
            .message = "PlayerJoinEvent was cancelled",
            .filtered = "PlayerJoinEvent was cancelled",
        };
        const serialized = try disconnect.serialize(&str);
        try network.sendPacket(connection, serialized);
        return;
    }

    try network.conduit.addPlayer(player);
    Raknet.Logger.INFO("Player {s} xuid: {s} logged in.", .{ data.identity_data.display_name, data.identity_data.xuid });

    {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();
        var packs = Protocol.ResourcePacksInfoPacket{
            .forceDisableVibrantVisuals = false,
            .hasAddons = false,
            .hasScripts = false,
            .mustAccept = false,
            .packs = &[_]Protocol.ResourcePackDescriptor{},
            .worldTemplateUuid = "00000000-0000-0000-0000-000000000000",
            .worldTemplateVersion = "",
        };
        const serialized = try packs.serialize(&str);
        try network.sendPacket(connection, serialized);
    }
}
