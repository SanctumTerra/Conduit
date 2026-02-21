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
    Raknet.Logger.INFO("PACKET {any}", .{request});

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
