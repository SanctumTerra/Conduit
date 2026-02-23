const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const inventory = @import("../../entity/traits/inventory.zig");

pub fn handleMobEquipment(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    var packet = try Protocol.MobEquipmentPacket.deserialize(stream);
    defer packet.deinit(stream.allocator);
    const player = network.conduit.getPlayerByConnection(connection) orelse return;

    if (player.entity.getTraitState(inventory.InventoryTrait)) |state| {
        inventory.setHeldItem(state, &player.entity, packet.selected_slot);
    }
}
