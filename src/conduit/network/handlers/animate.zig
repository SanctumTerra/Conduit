const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Player = @import("../../player/player.zig").Player;

pub fn handleAnimate(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = Protocol.AnimatePacket.deserialize(stream) catch return;

    var out_stream = BinaryStream.init(network.allocator, null, null);
    defer out_stream.deinit();

    const out_packet = Protocol.AnimatePacket{
        .action = packet.action,
        .runtime_entity_id = @intCast(player.runtimeId),
        .data = packet.data,
        .swing_source = packet.swing_source,
    };
    const serialized = try out_packet.serialize(&out_stream);

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |other| {
        if (other.runtimeId == player.runtimeId) continue;
        if (!other.spawned) continue;
        try network.sendPacket(other.connection, serialized);
    }
}
