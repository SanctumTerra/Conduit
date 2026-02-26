const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const InventoryTrait = @import("../../entity/traits/inventory.zig");
const BlockPermutation = @import("../../world/block/block-permutation.zig").BlockPermutation;
const applyTraitsForBlock = @import("../../world/block/traits/trait.zig").applyTraitsForBlock;
const resolveWithRotation = @import("../../world/block/traits/rotation.zig").resolveWithRotation;
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
            const world = network.conduit.getWorld("world") orelse return;
            const dimension = world.getDimension("overworld") orelse return;

            if (dimension.getBlockPtr(packet.blockPosition)) |clicked_block| {
                if (!clicked_block.fireEvent(.Interact, .{ clicked_block, player })) return;
            }

            const inv_state = player.entity.getTraitState(InventoryTrait.InventoryTrait) orelse return;
            const held = InventoryTrait.getHeldItem(inv_state) orelse return;

            const identifier = held.item_type.identifier;
            const base_permutation = BlockPermutation.resolve(player.entity.allocator, identifier, null) catch return;

            if (std.mem.eql(u8, base_permutation.identifier, "minecraft:air")) return;

            const permutation = resolveWithRotation(player.entity.allocator, base_permutation, player.entity.rotation.y);

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

            try applyTraitsForBlock(player.entity.allocator, dimension, pos);

            if (player.gamemode != .Creative) {
                inv_state.container.base.removeItem(inv_state.selected_slot, 1);
            }

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
        .CreativePlayerDestroyBlock => {
            const world = network.conduit.getWorld("world") orelse return;
            const dimension = world.getDimension("overworld") orelse return;
            const pos = packet.blockPosition;

            const perm = dimension.getPermutation(pos, 0) catch return;
            if (std.mem.eql(u8, perm.identifier, "minecraft:air")) return;

            var break_event = Events.BlockBreakEvent{
                .player = player,
                .position = pos,
                .permutation = perm,
            };
            if (!network.conduit.events.emit(.BlockBreak, &break_event)) return;

            const air = BlockPermutation.resolve(player.entity.allocator, "minecraft:air", null) catch return;
            try dimension.setPermutation(pos, air, 0);

            const air_id: u32 = @bitCast(air.network_id);
            const snapshots = network.conduit.getPlayerSnapshots();
            for (snapshots) |p| {
                if (!p.spawned) continue;
                var s = BinaryStream.init(network.allocator, null, null);
                defer s.deinit();
                const update = Protocol.UpdateBlockPacket{
                    .position = pos,
                    .networkBlockId = air_id,
                };
                const serialized = try update.serialize(&s);
                try network.sendPacket(p.connection, serialized);
            }

            const perm_id: u32 = @bitCast(perm.network_id);
            var ev_stream = BinaryStream.init(network.allocator, null, null);
            defer ev_stream.deinit();
            const ev_pkt = Protocol.LevelEventPacket{
                .event = .ParticlesDestroyBlock,
                .position = pos.toVector3f(),
                .data = @bitCast(perm_id),
            };
            const ev_serialized = ev_pkt.serialize(&ev_stream) catch return;
            for (snapshots) |p| {
                if (!p.spawned) continue;
                network.sendPacket(p.connection, ev_serialized) catch {};
            }
        },
        else => {
            Raknet.Logger.DEBUG("Unhandled PlayerAction: {any}", .{packet.action});
        },
    }
}
