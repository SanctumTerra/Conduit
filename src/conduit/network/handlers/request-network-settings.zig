const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleNetworkSettings(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const request = try Protocol.RequestNetworkSettingsPacket.deserialize(stream);
    if (request.protocol != Protocol.PROTOCOL) {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        var reason: Protocol.DisconnectReason = .OutdatedClient;
        if (request.protocol > Protocol.PROTOCOL) reason = .OutdatedServer;

        var disconnect = Protocol.DisconnectPacket{
            .hideScreen = true,
            .reason = reason,
        };
        const serialized = try disconnect.serialize(&str);
        try network.sendPacket(connection, serialized);
        return;
    }

    var write = BinaryStream.init(network.allocator, null, null);
    defer write.deinit();

    var response = Protocol.NetworkSettingsPacket{
        .clientScalar = 0,
        .compressionThreshold = network.options.compressionThreshold,
        .compressionMethod = network.options.compressionMethod,
        .clientThreshold = 0,
        .clientThrottle = false,
    };
    const packet = try response.serialize(&write);
    try network.sendUncompressedPacket(connection, packet);
}
