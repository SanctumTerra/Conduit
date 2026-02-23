const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const inventory = @import("../../entity/traits/inventory.zig");

pub fn handleInteract(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = Protocol.InteractPacket.deserialize(stream) catch return;

    switch (packet.action) {
        .OpenInventory => {
            if (player.entity.getTraitState(inventory.InventoryTrait)) |state| {
                _ = state.container.show(player);
            }
        },
        else => {},
    }
}
