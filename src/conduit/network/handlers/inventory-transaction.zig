const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Player = @import("../../player/player.zig").Player;
const InventoryTrait = @import("../../entity/traits/inventory.zig");
const BlockPermutation = @import("../../world/block/block-permutation.zig").BlockPermutation;
const applyTraitsForBlock = @import("../../world/block/traits/trait.zig").applyTraitsForBlock;
const resolveWithPlacement = @import("../../world/block/traits/rotation.zig").resolveWithPlacement;
const placeUpperBlock = @import("../../world/block/traits/rotation.zig").placeUpperBlock;
const Events = @import("../../events/types.zig");

pub fn handleInventoryTransaction(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.InventoryTransactionPacket.deserialize(stream);

    switch (packet.transactionType) {
        .UseItem => {
            const data = packet.transactionData.useItem;
            try handleUseItem(network, player, data);
        },
        .UseItemOnEntity => {
            const data = packet.transactionData.useItemOnEntity;
            if (data.actionType == 1) {
                const target = network.conduit.getEntityByRuntimeId(@bitCast(data.targetEntityRuntimeId)) orelse return;

                const dx = target.position.x - player.entity.position.x;
                const dz = target.position.z - player.entity.position.z;
                const dist = @sqrt(dx * dx + dz * dz);
                if (dist > 0.001) {
                    const kb_strength: f32 = 0.3;
                    target.motion.x = (dx / dist) * kb_strength;
                    target.motion.y = 0.3;
                    target.motion.z = (dz / dist) * kb_strength;

                    broadcastMotion(network, target);
                }

                target.fireEvent(.Damage, .{ target, @as(f32, 1.0) });
            }
        },
        else => {},
    }
}

fn handleUseItem(
    network: *NetworkHandler,
    player: *Player,
    data: Protocol.InventoryTransactionData.UseItemTransactionData,
) !void {
    if (data.actionType != 0) return;

    const world = network.conduit.getWorld("world") orelse return;
    const dimension = world.getDimension("overworld") orelse return;

    if (!player.entity.flags.getFlag(.Sneaking)) {
        if (dimension.getBlockPtr(data.blockPosition)) |clicked_block| {
            if (!clicked_block.fireEvent(.Interact, .{ clicked_block, player })) return;
        }
    }

    const inv_state = player.entity.getTraitState(InventoryTrait.InventoryTrait) orelse return;
    const held = InventoryTrait.getHeldItem(inv_state) orelse return;

    const identifier = held.item_type.identifier;
    const base_permutation = BlockPermutation.resolve(player.entity.allocator, identifier, null) catch return;

    if (std.mem.eql(u8, base_permutation.identifier, "minecraft:air")) return;

    const permutation = resolveWithPlacement(player.entity.allocator, base_permutation, .{
        .yaw = player.entity.rotation.y,
        .pitch = player.entity.rotation.x,
        .block_face = data.blockFace,
        .clicked_position = data.clickedPosition,
    });

    const face = data.blockFace;
    const pos = Protocol.BlockPosition{
        .x = data.blockPosition.x + if (face == 5) @as(i32, 1) else if (face == 4) @as(i32, -1) else @as(i32, 0),
        .y = data.blockPosition.y + if (face == 1) @as(i32, 1) else if (face == 0) @as(i32, -1) else @as(i32, 0),
        .z = data.blockPosition.z + if (face == 3) @as(i32, 1) else if (face == 2) @as(i32, -1) else @as(i32, 0),
    };

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
    try placeUpperBlock(player.entity.allocator, dimension, pos, permutation);

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
}

fn broadcastMotion(network: *NetworkHandler, entity: *const @import("../../entity/entity.zig").Entity) void {
    const allocator = network.conduit.allocator;
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    const motion_packet = Protocol.SetActorMotionPacket{
        .runtimeEntityId = @bitCast(entity.runtime_id),
        .motion = entity.motion,
    };
    const serialized = motion_packet.serialize(&stream) catch return;

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |p| {
        if (!p.spawned) continue;
        network.sendPacket(p.connection, serialized) catch {};
    }
}
