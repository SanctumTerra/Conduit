const Raknet = @import("Raknet");
const std = @import("std");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const MoveDeltaFlags = Protocol.MoveDeltaFlags;
const InventoryTrait = @import("../../entity/traits/inventory.zig");
const BlockPermutation = @import("../../world/block/block-permutation.zig").BlockPermutation;
const applyTraitsForBlock = @import("../../world/block/traits/trait.zig").applyTraitsForBlock;
const Events = @import("../../events/types.zig");

pub fn handlePlayerAuthInput(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.PlayerAuthInputPacket.deserialize(stream);

    player.entity.position = packet.position;
    player.entity.rotation = packet.rotation;
    player.entity.motion = .{ .x = packet.motion.x, .y = 0, .z = packet.motion.y };
    player.entity.head_yaw = packet.headYaw;

    {
        var flags_changed = false;
        if (packet.inputData.hasFlag(.StartSneaking)) {
            player.entity.flags.setFlag(.Sneaking, true);
            flags_changed = true;
        }
        if (packet.inputData.hasFlag(.StopSneaking)) {
            player.entity.flags.setFlag(.Sneaking, false);
            flags_changed = true;
        }
        if (flags_changed) try player.broadcastActorFlags();
    }

    if (packet.inputData.hasFlag(.PerformItemInteraction)) {
        if (packet.itemTransaction) |transaction| {
            try handleItemUseTransaction(network, player, transaction);
        }
    }

    var move_stream = BinaryStream.init(network.allocator, null, null);
    defer move_stream.deinit();

    const move_packet = Protocol.MoveActorDeltaPacket{
        .runtime_id = @intCast(player.entity.runtime_id),
        .flags = MoveDeltaFlags.All,
        .x = packet.position.x,
        .y = packet.position.y,
        .z = packet.position.z,
        .pitch = packet.rotation.x,
        .yaw = packet.rotation.y,
        .head_yaw = packet.headYaw,
    };
    const serialized = try move_packet.serialize(&move_stream);

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        if (!other.spawned) continue;
        try network.sendPacket(other.connection, serialized);
    }
}

const Player = @import("../../player/player.zig").Player;

fn handleItemUseTransaction(
    network: *NetworkHandler,
    player: *Player,
    transaction: Protocol.ItemUseTransaction,
) !void {
    if (transaction.actionType != 0) return;

    const world = network.conduit.getWorld("world") orelse return;
    const dimension = world.getDimension("overworld") orelse return;

    if (dimension.getBlockPtr(transaction.blockPosition)) |cb| {
        if (!cb.fireEvent(.Interact, .{ cb, player })) return;
    }

    const inv_state = player.entity.getTraitState(InventoryTrait.InventoryTrait) orelse return;
    const held = InventoryTrait.getHeldItem(inv_state) orelse return;

    const identifier = held.item_type.identifier;
    const permutation = BlockPermutation.resolve(player.entity.allocator, identifier, null) catch return;

    if (std.mem.eql(u8, permutation.identifier, "minecraft:air")) return;

    const face = transaction.blockFace;
    const pos = Protocol.BlockPosition{
        .x = transaction.blockPosition.x + if (face == 5) @as(i32, 1) else if (face == 4) @as(i32, -1) else @as(i32, 0),
        .y = transaction.blockPosition.y + if (face == 1) @as(i32, 1) else if (face == 0) @as(i32, -1) else @as(i32, 0),
        .z = transaction.blockPosition.z + if (face == 3) @as(i32, 1) else if (face == 2) @as(i32, -1) else @as(i32, 0),
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

    inv_state.container.base.removeItem(inv_state.selected_slot, 1);

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
