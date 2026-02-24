const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const InventoryTrait = @import("../../entity/traits/inventory.zig");
const BlockPermutation = @import("../../world/block/block-permutation.zig").BlockPermutation;
const Events = @import("../../events/types.zig");

pub fn handlePlayerAction(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.PlayerActionPacket.deserialize(stream);

    switch (packet.action) {
        .Respawn => {},
        .DimensionChangeDone => {},
        .StartItemUseOn => {
            const inv_state = player.entity.getTraitState(InventoryTrait.InventoryTrait) orelse return;
            const held = InventoryTrait.getHeldItem(inv_state) orelse return;

            const identifier = held.item_type.identifier;
            const permutation = BlockPermutation.resolve(player.entity.allocator, identifier, null) catch return;

            if (std.mem.eql(u8, permutation.identifier, "minecraft:air")) return;

            const world = network.conduit.getWorld("world") orelse return;
            const dimension = world.getDimension("overworld") orelse return;
            const pos = packet.resultPosition;

            var block = dimension.getBlock(pos);
            if (!block.fireEvent(.Place, .{ &block, player })) return;

            var place_event = Events.BlockPlaceEvent{
                .player = player,
                .position = pos,
                .permutation = permutation,
            };
            if (!network.conduit.events.emit(.BlockPlace, &place_event)) return;

            try dimension.setPermutation(pos, permutation, 0);

            _ = inv_state.container.base.removeItem(inv_state.selected_slot, 1);

            const network_id: u32 = @bitCast(permutation.network_id);
            const snapshots = network.conduit.getPlayerSnapshots();
            for (snapshots) |p| {
                if (!p.spawned) continue;
                var s = BinaryStream.init(network.allocator, null, null);
                defer s.deinit();
                const update = Protocol.UpdateBlockPacket{
                    .position = pos,
                    .networkBlockId = network_id,
                };
                const serialized = try update.serialize(&s);
                try network.sendPacket(p.connection, serialized);
            }
        },
        .StopItemUseOn => {},
        else => {
            Raknet.Logger.DEBUG("Unhandled PlayerAction: {any}", .{packet.action});
        },
    }
}
