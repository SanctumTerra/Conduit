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
    _ = try stream.readVarInt();
    _ = try stream.readVarLong();
    Protocol.NetworkItemStackDescriptor.skip(stream) catch {};
    const slot = try stream.readUint8();
    const selected_slot = try stream.readUint8();
    _ = try stream.readInt8();

    const player = network.conduit.getPlayerByConnection(connection) orelse return;

    const state = player.entity.getTraitState(inventory.InventoryTrait) orelse return;
    inventory.setHeldItem(state, &player.entity, selected_slot);

    const held = inventory.getHeldItem(state);
    const item_descriptor = if (held) |item| item.toNetworkStack() else Protocol.NetworkItemStackDescriptor{
        .network = 0,
        .stackSize = null,
        .metadata = null,
        .itemStackId = null,
        .networkBlockId = null,
        .extras = null,
    };

    var out_stream = BinaryStream.init(network.allocator, null, null);
    defer out_stream.deinit();

    const out_packet = Protocol.MobEquipmentPacket{
        .runtime_entity_id = @intCast(player.entity.runtime_id),
        .item = item_descriptor,
        .slot = slot,
        .selected_slot = selected_slot,
        .container_id = .Inventory,
    };
    const serialized = try out_packet.serialize(&out_stream);

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        if (!other.spawned) continue;
        if (!other.visible_players.contains(player.entity.runtime_id)) continue;
        try network.sendPacket(other.connection, serialized);
    }
}
