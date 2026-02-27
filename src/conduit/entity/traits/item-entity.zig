const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const Player = @import("../../player/player.zig").Player;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const ItemType = @import("../../items/item-type.zig").ItemType;
const InventoryTrait = @import("./inventory.zig");
const Container = @import("../../container/container.zig").Container;

pub const State = struct {
    item_identifier: []const u8,
    count: u16,
    pickup_delay: u32,
    lifetime: u32,
    pending_remove: bool,
};

const MAGNET_DISTANCE: f32 = 2.5;
const COLLECT_DISTANCE: f32 = 0.8;
const MERGE_DISTANCE: f32 = 3.0;
const DESPAWN_TICKS: u32 = 6000;
const PLAYER_EYE_HEIGHT: f32 = 1.62;

fn onTick(state: *State, entity: *Entity) void {
    if (state.pending_remove) return;

    state.lifetime += 1;

    if (state.lifetime >= DESPAWN_TICKS) {
        markForRemoval(state, entity);
        return;
    }

    if (state.pickup_delay > 0) {
        state.pickup_delay -= 1;
        return;
    }

    const dimension = entity.dimension orelse return;
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
            const item_type = ItemType.get(state.item_identifier) orelse continue;
            const inv_state = player.entity.getTraitState(InventoryTrait.InventoryTrait) orelse continue;

            if (!tryStackIntoInventory(&inv_state.container.base, item_type, state.count, player.entity.allocator)) continue;
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

fn tryStackIntoInventory(container: *Container, item_type: *ItemType, count: u16, allocator: std.mem.Allocator) bool {
    var remaining: u16 = count;

    if (item_type.stackable) {
        for (container.storage, 0..) |*slot, i| {
            if (remaining == 0) break;
            if (slot.*) |*existing| {
                if (existing.item_type == item_type and
                    existing.metadata == 0 and
                    existing.nbt == null and
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

        const to_place = @min(remaining, item_type.max_stack_size);
        container.storage[empty_slot] = ItemStack.init(allocator, item_type, .{ .stackSize = to_place });
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

pub fn tryMergeNearby(dimension: *Dimension, identifier: []const u8, count: u16, position: Protocol.Vector3f) ?*Entity {
    var it = dimension.entities.valueIterator();
    while (it.next()) |ent| {
        const other = ent.*;
        if (!std.mem.eql(u8, other.entity_type.identifier, "minecraft:item")) continue;
        const other_state = other.getTraitState(ItemEntityTrait) orelse continue;
        if (other_state.pending_remove) continue;
        if (!std.mem.eql(u8, other_state.item_identifier, identifier)) continue;

        const item_type = ItemType.get(identifier) orelse continue;
        if (other_state.count + count > item_type.max_stack_size) continue;

        const dist = other.position.distance(position);
        if (dist > MERGE_DISTANCE) continue;

        other_state.count += count;
        return other;
    }
    return null;
}

pub const ItemEntityTrait = EntityTrait(State, .{
    .identifier = "item_entity",
    .onTick = onTick,
});
