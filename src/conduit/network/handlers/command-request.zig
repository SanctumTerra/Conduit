const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleCommandRequest(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const request = try Protocol.CommandRequestPacket.deserialize(stream);
    const player = network.conduit.getPlayerByConnection(connection) orelse return;

    const result = network.conduit.command_registry.dispatch(
        player,
        network,
        request.command_line,
        request.origin_type,
        request.uuid,
        request.request_id,
    );

    if (!result.success and result.message.len > 0) {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        const msgs = [_]Protocol.CommandOutputMessage{
            .{ .success = false, .message = result.message, .parameters = &.{} },
        };

        var output = Protocol.CommandOutputPacket{
            .origin_type = request.origin_type,
            .uuid = request.uuid,
            .request_id = request.request_id,
            .player_unique_id = request.player_unique_id,
            .output_type = "alloutput",
            .success_count = 0,
            .messages = &msgs,
        };

        const serialized = try output.serialize(&str);
        try network.sendPacket(connection, serialized);
    }
}
