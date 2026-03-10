const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const Player = @import("../../player/player.zig").Player;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const InventoryTrait = @import("./inventory.zig");
const GravityTrait = @import("./gravity.zig").GravityTrait;
const Container = @import("../../container/container.zig").Container;

pub const State = struct {
    stack: ItemStack,
    pickup_delay: u32,
    lifetime: u32,
    pending_remove: bool,
};

const MAGNET_DISTANCE: f32 = 2.5;
const COLLECT_DISTANCE: f32 = 0.8;
const MERGE_DISTANCE: f32 = 3.0;
const DESPAWN_TICKS: u32 = 6000;
const PLAYER_EYE_HEIGHT: f32 = 1.62;

fn canMergeGroundedItems(
    existing: *const ItemStack,
    existing_pending_remove: bool,
    existing_grounded: bool,
    incoming: *const ItemStack,
    incoming_grounded: bool,
    dist: f32,
) bool {
    if (existing_pending_remove) return false;
    if (!existing_grounded or !incoming_grounded) return false;
    if (!existing.isStackCompatible(incoming)) return false;
    if (existing.stackSize + incoming.stackSize > existing.item_type.max_stack_size) return false;
    return dist <= MERGE_DISTANCE;
}

fn onTick(state: *State, entity: *Entity) void {
    if (state.pending_remove) return;

    state.lifetime += 1;

    if (state.lifetime >= DESPAWN_TICKS) {
        markForRemoval(state, entity);
        return;
    }

    const dimension = entity.dimension orelse return;
    tryMergeGroundedEntity(dimension, entity, state);

    if (state.pending_remove) return;

    if (state.pickup_delay > 0) {
        state.pickup_delay -= 1;
        return;
    }

    const conduit = dimension.world.conduit;

    conduit.players_mutex.lock();
    const player_count = conduit.players.count();
    conduit.players_mutex.unlock();

    if (player_count == 0) return;

    const snapshots = conduit.getPlayerSnapshots();

    for (snapshots) |player| {
        if (!player.spawned) continue;
        if (player.gamemode == .Spectator) continue;
        const feet_pos = Protocol.Vector3f.init(player.entity.position.x, player.entity.position.y - PLAYER_EYE_HEIGHT, player.entity.position.z);
        const dist = feet_pos.distance(entity.position);
        if (dist > MAGNET_DISTANCE) continue;

        if (dist <= COLLECT_DISTANCE) {
            const inv_state = player.entity.getTraitState(InventoryTrait.InventoryTrait) orelse continue;

            if (!tryStackIntoInventory(&inv_state.container.base, &state.stack)) continue;
            inv_state.container.sendOwnerContentUpdate();

            broadcastPickup(dimension, entity, player);
            markForRemoval(state, entity);
            return;
        }

        const dir = feet_pos.subtract(entity.position);
        const speed: f32 = 0.4;
        entity.motion = Protocol.Vector3f.init(
            dir.x / dist * speed,
            dir.y / dist * speed + 0.06,
            dir.z / dist * speed,
        );
        return;
    }
}

fn markForRemoval(state: *State, entity: *Entity) void {
    state.pending_remove = true;
    const dimension = entity.dimension orelse return;
    dimension.pending_removals.append(dimension.allocator, entity.runtime_id) catch {};
}

fn tryStackIntoInventory(container: *Container, stack: *const ItemStack) bool {
    var remaining: u16 = stack.stackSize;

    if (stack.item_type.stackable) {
        for (container.storage, 0..) |*slot, i| {
            if (remaining == 0) break;
            if (slot.*) |*existing| {
                if (existing.isStackCompatible(stack) and
                    existing.stackSize < existing.item_type.max_stack_size)
                {
                    const space = existing.item_type.max_stack_size - existing.stackSize;
                    const to_add = @min(space, remaining);
                    existing.stackSize += to_add;
                    remaining -= to_add;
                    container.updateSlot(@intCast(i));
                }
            }
        }
    }

    while (remaining > 0) {
        const empty_slot = for (container.storage, 0..) |slot, i| {
            if (slot == null) break i;
        } else break;

        const to_place = @min(remaining, stack.item_type.max_stack_size);
        container.storage[empty_slot] = stack.cloneWithCount(container.allocator, to_place) catch break;
        remaining -= to_place;
        container.updateSlot(@intCast(empty_slot));
    }

    return remaining == 0;
}

fn broadcastPickup(dimension: *Dimension, entity: *Entity, player: *Player) void {
    const conduit = dimension.world.conduit;
    var stream = BinaryStream.init(conduit.allocator, null, null);
    defer stream.deinit();

    const packet = Protocol.TakeItemActorPacket{
        .itemEntityRuntimeId = @bitCast(entity.runtime_id),
        .takerEntityRuntimeId = @bitCast(player.entity.runtime_id),
    };
    const serialized = packet.serialize(&stream) catch return;

    const snapshots = conduit.getPlayerSnapshots();
    for (snapshots) |p| {
        if (!p.spawned) continue;
        conduit.network.sendPacket(p.connection, serialized) catch {};
    }
}

fn tryMergeGroundedEntity(dimension: *Dimension, entity: *Entity, state: *State) void {
    const gravity_state = entity.getTraitState(GravityTrait) orelse return;
    if (!gravity_state.on_ground) return;

    const other = tryMergeNearbyGrounded(dimension, entity, state, true) orelse return;
    const other_state = other.getTraitState(ItemEntityTrait) orelse return;

    other_state.stack.stackSize += state.stack.stackSize;
    other_state.pickup_delay = @max(other_state.pickup_delay, state.pickup_delay);
    other_state.lifetime = @min(other_state.lifetime, state.lifetime);

    refreshMergedItemEntity(dimension, other);
    markForRemoval(state, entity);
}

fn refreshMergedItemEntity(dimension: *Dimension, entity: *Entity) void {
    const state = entity.getTraitState(ItemEntityTrait) orelse return;
    const conduit = dimension.world.conduit;

    var stream = BinaryStream.init(conduit.allocator, null, null);
    defer stream.deinit();

    const packet = Protocol.AddItemActorPacket{
        .uniqueEntityId = entity.unique_id,
        .runtimeEntityId = @bitCast(entity.runtime_id),
        .item = state.stack.toNetworkStack(),
        .position = entity.position,
        .velocity = entity.motion,
    };
    const serialized = packet.serialize(&stream, conduit.allocator) catch return;

    const snapshots = conduit.getPlayerSnapshots();
    for (snapshots) |player| {
        if (!player.spawned) continue;
        conduit.network.sendPacket(player.connection, serialized) catch {};
    }
}

fn tryMergeNearbyGrounded(dimension: *Dimension, entity: *Entity, state: *const State, incoming_grounded: bool) ?*Entity {
    var it = dimension.entities.valueIterator();
    while (it.next()) |ent| {
        const other = ent.*;
        if (other == entity) continue;
        if (!std.mem.eql(u8, other.entity_type.identifier, "minecraft:item")) continue;
        const other_state = other.getTraitState(ItemEntityTrait) orelse continue;
        const other_gravity = other.getTraitState(GravityTrait) orelse continue;

        const dist = other.position.distance(entity.position);
        if (!canMergeGroundedItems(&other_state.stack, other_state.pending_remove, other_gravity.on_ground, &state.stack, incoming_grounded, dist)) continue;

        return other;
    }
    return null;
}

fn onDetach(state: *State, _: *Entity) void {
    state.stack.deinit();
}

pub const ItemEntityTrait = EntityTrait(State, .{
    .identifier = "item_entity",
    .onTick = onTick,
    .onDetach = onDetach,
});

test "grounded item merge rejects airborne items" {
    const stone = ItemStack.fromIdentifier(std.testing.allocator, "minecraft:stone", .{ .stackSize = 1 }) orelse return error.TestUnexpectedResult;
    defer {
        var item = stone;
        item.deinit();
    }

    const other = ItemStack.fromIdentifier(std.testing.allocator, "minecraft:stone", .{ .stackSize = 1 }) orelse return error.TestUnexpectedResult;
    defer {
        var item = other;
        item.deinit();
    }

    try std.testing.expect(!canMergeGroundedItems(&stone, false, false, &other, true, 0.5));
    try std.testing.expect(!canMergeGroundedItems(&stone, false, true, &other, false, 0.5));
}

test "grounded item merge accepts compatible grounded items in range" {
    const stone = ItemStack.fromIdentifier(std.testing.allocator, "minecraft:stone", .{ .stackSize = 1 }) orelse return error.TestUnexpectedResult;
    defer {
        var item = stone;
        item.deinit();
    }

    const other = ItemStack.fromIdentifier(std.testing.allocator, "minecraft:stone", .{ .stackSize = 1 }) orelse return error.TestUnexpectedResult;
    defer {
        var item = other;
        item.deinit();
    }

    try std.testing.expect(canMergeGroundedItems(&stone, false, true, &other, true, 0.5));
}
