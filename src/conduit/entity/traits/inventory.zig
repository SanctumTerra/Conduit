const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("../trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const Container = @import("../../container/container.zig").Container;
const EntityContainer = @import("../../container/entity-container.zig").EntityContainer;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;

pub const State = struct {
    container: EntityContainer,
    selected_slot: u8,
    opened: bool,
};

fn getPlayer(entity: *Entity) ?*Player {
    if (!std.mem.eql(u8, entity.entity_type.identifier, "minecraft:player")) return null;
    return @fieldParentPtr("entity", entity);
}

fn onAttach(state: *State, entity: *Entity) void {
    const player = getPlayer(entity) orelse return;
    state.container = EntityContainer.init(entity.allocator, player, .Inventory, 36) catch return;
    state.container.base.identifier = .Inventory;
}

fn onDetach(state: *State, _: *Entity) void {
    state.container.deinit();
}

fn onSpawn(state: *State, entity: *Entity) void {
    const player = getPlayer(entity) orelse return;
    if (player.spawned) state.container.update();
}

fn onTick(state: *State, _: *Entity) void {
    const occupants = state.container.base.getAllOccupants();
    const has_occupants = occupants.count() > 0;

    if (!state.opened and has_occupants) {
        state.opened = true;
    }
    if (state.opened and !has_occupants) {
        state.opened = false;
    }
}

fn onContainerUpdate(state: *State, _: *Entity, container: *Container) void {
    if (container != &state.container.base) return;
}

pub fn getHeldItem(state: *const State) ?*const ItemStack {
    return state.container.base.getItem(state.selected_slot);
}

pub fn setHeldItem(state: *State, entity: *Entity, slot: u8) void {
    const player = getPlayer(entity) orelse return;
    state.selected_slot = slot;

    const held = getHeldItem(state);
    const item_descriptor = if (held) |item| item.toNetworkStack() else Protocol.NetworkItemStackDescriptor{
        .network = 0,
        .stackSize = null,
        .metadata = null,
        .itemStackId = null,
        .networkBlockId = null,
        .extras = null,
    };

    var stream = BinaryStream.init(entity.allocator, null, null);
    defer stream.deinit();

    const packet = Protocol.MobEquipmentPacket{
        .runtime_entity_id = @bitCast(entity.runtime_id),
        .item = item_descriptor,
        .slot = slot,
        .selected_slot = slot,
        .container_id = .Inventory,
    };
    const serialized = packet.serialize(&stream) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};
}

pub const InventoryTrait = EntityTrait(State, .{
    .identifier = "inventory",
    .onAttach = onAttach,
    .onDetach = onDetach,
    .onSpawn = onSpawn,
    .onTick = onTick,
    .onContainerUpdate = onContainerUpdate,
});
