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

    var out_stream = BinaryStream.init(network.allocator, null, null);
    defer out_stream.deinit();

    const out_packet = Protocol.MobEquipmentPacket{
        .runtime_entity_id = @intCast(player.entity.runtime_id),
        .item = packet.item,
        .slot = packet.selected_slot,
        .selected_slot = packet.selected_slot,
        .container_id = .Inventory,
    };
    const serialized = try out_packet.serialize(&out_stream);

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        if (!other.spawned) continue;
        try network.sendPacket(other.connection, serialized);
    }
}
