const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleClientCacheStatus(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const status = try Protocol.ClientCacheStatusPacket.deserialize(stream);
    Raknet.Logger.INFO("ClientCacheStatus: enabled={}", .{status.enabled});

    var write = BinaryStream.init(network.allocator, null, null);
    defer write.deinit();

    var response = Protocol.ClientCacheStatusPacket{
        .enabled = status.enabled,
    };
    const packet = try response.serialize(&write);
    try network.sendPacket(connection, packet);
}
