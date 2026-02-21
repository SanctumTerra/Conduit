const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;

pub fn handleSetLocalPlayerAsInitialized(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    _: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    player.onSpawn();
}
