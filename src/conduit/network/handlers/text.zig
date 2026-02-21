const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleTextPacket(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const text = try Protocol.TextPacket.deserialize(stream);
    Raknet.Logger.INFO("PACKET {any}", .{text});

    if (text.textType == .Chat) {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        const sender = network.conduit.getPlayerByConnection(connection) orelse return;

        var packet = Protocol.TextPacket{
            .textType = .Chat,
            .sourceName = sender.username,
            .message = text.message,
            .xuid = sender.xuid,
        };

        const serialized = try packet.serialize(&str);

        var it = network.conduit.players.valueIterator();
        while (it.next()) |player| {
            try network.sendPacket(player.*.connection, serialized);
        }
    }
}
