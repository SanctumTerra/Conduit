const std = @import("std");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const EntityContainer = @import("../../container/entity-container.zig").EntityContainer;

pub const State = struct {
    container: EntityContainer,
};

fn getPlayer(entity: *Entity) ?*Player {
    if (!std.mem.eql(u8, entity.entity_type.identifier, "minecraft:player")) return null;
    return @fieldParentPtr("entity", entity);
}

fn onAttach(state: *State, entity: *Entity) void {
    const player = getPlayer(entity) orelse return;
    state.container = EntityContainer.init(entity.allocator, player, .Inventory, 1) catch return;
    state.container.base.identifier = .Ui;
}

fn onDetach(state: *State, _: *Entity) void {
    state.container.deinit();
}

pub const CursorTrait = EntityTrait(State, .{
    .identifier = "cursor",
    .onAttach = onAttach,
    .onDetach = onDetach,
});
