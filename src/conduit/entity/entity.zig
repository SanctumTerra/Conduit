const std = @import("std");
const Protocol = @import("protocol");
const CompoundTag = @import("nbt").CompoundTag;
const EntityType = @import("./entity-type.zig").EntityType;
const EntityActorFlags = @import("./metadata/actor-flags.zig").EntityActorFlags;
const Attributes = @import("./metadata/attributes.zig").Attributes;
const trait_mod = @import("./traits/trait.zig");
const EntityTraitInstance = trait_mod.EntityTraitInstance;
const Event = trait_mod.Event;
const Player = @import("../player/player.zig").Player;
const Container = @import("../container/container.zig").Container;
const Dimension = @import("../world/dimension/dimension.zig").Dimension;

var nextUniqueId: i64 = 1;

pub const Entity = struct {
    allocator: std.mem.Allocator,
    entity_type: *const EntityType,
    runtime_id: i64,
    unique_id: i64,
    position: Protocol.Vector3f,
    rotation: Protocol.Vector2f,
    motion: Protocol.Vector3f,
    head_yaw: f32,
    flags: EntityActorFlags,
    attributes: Attributes,
    traits: std.ArrayListUnmanaged(EntityTraitInstance),
    dimension: ?*Dimension,
    name_tag: []const u8 = "",
    nametag_always_visible: bool = false,

    pub fn init(allocator: std.mem.Allocator, entity_type: *const EntityType, dimension: ?*Dimension) Entity {
        const uid = @atomicRmw(i64, &nextUniqueId, .Add, 1, .monotonic);
        return .{
            .allocator = allocator,
            .entity_type = entity_type,
            .runtime_id = uid,
            .unique_id = uid,
            .position = Protocol.Vector3f.init(0, 0, 0),
            .rotation = Protocol.Vector2f.init(0, 0),
            .motion = Protocol.Vector3f.init(0, 0, 0),
            .head_yaw = 0.0,
            .flags = EntityActorFlags.init(),
            .attributes = Attributes.init(allocator),
            .traits = .{},
            .dimension = dimension,
        };
    }

    pub fn deinit(self: *Entity) void {
        for (self.traits.items) |instance| {
            if (instance.vtable.onDetach) |f| f(instance.ctx, self);
            if (instance.vtable.destroyFn) |f| f(instance.ctx, self.allocator);
        }
        self.traits.deinit(self.allocator);
        self.attributes.deinit();
    }

    pub fn addTrait(self: *Entity, instance: EntityTraitInstance) !void {
        try self.traits.append(self.allocator, instance);
        if (instance.vtable.onAttach) |f| f(instance.ctx, self);
    }

    pub fn removeTrait(self: *Entity, id: []const u8) void {
        for (self.traits.items, 0..) |instance, i| {
            if (std.mem.eql(u8, instance.identifier, id)) {
                if (instance.vtable.onDetach) |f| f(instance.ctx, self);
                _ = self.traits.swapRemove(i);
                return;
            }
        }
    }

    pub fn hasTrait(self: *const Entity, id: []const u8) bool {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, id)) return true;
        }
        return false;
    }

    pub fn getTrait(self: *const Entity, id: []const u8) ?EntityTraitInstance {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, id)) return instance;
        }
        return null;
    }

    pub fn getTraitState(self: *const Entity, comptime T: type) ?*T.TraitState {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, T.identifier)) {
                return @ptrCast(@alignCast(instance.ctx));
            }
        }
        return null;
    }

    pub fn fireEvent(self: *Entity, comptime event: Event, args: anytype) Event.ReturnType(event) {
        for (self.traits.items) |instance| {
            if (instance.vtable.get(event)) |f| {
                const result = @call(.auto, f, .{instance.ctx} ++ args);
                if (Event.ReturnType(event) == bool) {
                    if (!result) return false;
                }
            }
        }
        if (Event.ReturnType(event) == bool) return true;
    }

    pub fn setNameTag(self: *Entity, tag: []const u8) void {
        self.name_tag = tag;
    }

    pub fn getNameTag(self: *const Entity) []const u8 {
        return self.name_tag;
    }

    pub fn setNameTagAlwaysVisible(self: *Entity, visible: bool) void {
        self.nametag_always_visible = visible;
    }

    pub fn despawn(self: *Entity) void {
        self.fireEvent(.Despawn, .{self});
        // TODO: remove from dimension entity list
    }
};
