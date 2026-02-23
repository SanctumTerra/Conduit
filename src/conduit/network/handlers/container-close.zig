const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleContainerClose(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.ContainerClosePacket.deserialize(stream);

    if (player.opened_container) |container| {
        if (container.occupants.get(player)) |_| {
            container.close(player, false);
        } else {
            player.opened_container = null;
            var str = BinaryStream.init(network.allocator, null, null);
            defer str.deinit();

            const response = Protocol.ContainerClosePacket{
                .identifier = packet.identifier,
                .container_type = packet.container_type,
                .server_initiated = false,
            };
            const serialized = try response.serialize(&str);
            try network.sendPacket(connection, serialized);
        }
    } else {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        const response = Protocol.ContainerClosePacket{
            .identifier = packet.identifier,
            .container_type = packet.container_type,
            .server_initiated = true,
        };
        const serialized = try response.serialize(&str);
        try network.sendPacket(connection, serialized);
    }
}
