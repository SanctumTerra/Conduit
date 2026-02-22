const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Events = @import("../../events/root.zig");

pub fn handleTextPacket(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const text = try Protocol.TextPacket.deserialize(stream);

    if (text.textType == .Chat) {
        const sender = network.conduit.getPlayerByConnection(connection) orelse return;

        var event = Events.types.PlayerChatEvent{
            .player = sender,
            .message = text.message,
        };
        if (!network.conduit.events.emit(.PlayerChat, &event)) return;

        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        var packet = Protocol.TextPacket{
            .textType = .Chat,
            .sourceName = sender.username,
            .message = event.message,
            .xuid = sender.xuid,
        };

        const serialized = try packet.serialize(&str);

        const snapshots = network.conduit.getPlayerSnapshots();
        for (snapshots) |p| {
            try network.sendPacket(p.connection, serialized);
        }
    }
}
