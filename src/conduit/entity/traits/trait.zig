const std = @import("std");
const Entity = @import("../entity.zig").Entity;
const EntityType = @import("../entity-type.zig").EntityType;
const Player = @import("../../player/player.zig").Player;
const Container = @import("../../container/container.zig").Container;
const CompoundTag = @import("nbt").CompoundTag;

pub const Event = enum {
    Attach,
    Detach,
    Tick,
    Spawn,
    Despawn,
    Damage,
    Death,
    Interact,
    ContainerUpdate,
    Serialize,
    Deserialize,

    pub fn VTableFnType(comptime event: Event) type {
        return switch (event) {
            .Attach, .Detach, .Tick, .Spawn, .Despawn, .Death => *const fn (*anyopaque, *Entity) void,
            .Damage => *const fn (*anyopaque, *Entity, f32) void,
            .Interact => *const fn (*anyopaque, *Entity, *Player) bool,
            .ContainerUpdate => *const fn (*anyopaque, *Entity, *Container) void,
            .Serialize => *const fn (*anyopaque, *CompoundTag) void,
            .Deserialize => *const fn (*anyopaque, *const CompoundTag) void,
        };
    }

    pub fn ReturnType(comptime event: Event) type {
        return switch (event) {
            .Interact => bool,
            else => void,
        };
    }

    pub fn fieldName(comptime event: Event) []const u8 {
        return switch (event) {
            .Attach => "onAttach",
            .Detach => "onDetach",
            .Tick => "onTick",
            .Spawn => "onSpawn",
            .Despawn => "onDespawn",
            .Damage => "onDamage",
            .Death => "onDeath",
            .Interact => "onInteract",
            .ContainerUpdate => "onContainerUpdate",
            .Serialize => "onSerialize",
            .Deserialize => "onDeserialize",
        };
    }
};

pub const EntityTraitVTable = struct {
    onAttach: ?Event.VTableFnType(.Attach) = null,
    onDetach: ?Event.VTableFnType(.Detach) = null,
    onTick: ?Event.VTableFnType(.Tick) = null,
    onSpawn: ?Event.VTableFnType(.Spawn) = null,
    onDespawn: ?Event.VTableFnType(.Despawn) = null,
    onDamage: ?Event.VTableFnType(.Damage) = null,
    onDeath: ?Event.VTableFnType(.Death) = null,
    onInteract: ?Event.VTableFnType(.Interact) = null,
    onContainerUpdate: ?Event.VTableFnType(.ContainerUpdate) = null,
    onSerialize: ?Event.VTableFnType(.Serialize) = null,
    onDeserialize: ?Event.VTableFnType(.Deserialize) = null,
    destroyFn: ?*const fn (*anyopaque, std.mem.Allocator) void = null,

    pub fn get(self: *const EntityTraitVTable, comptime event: Event) ?Event.VTableFnType(event) {
        return @field(self, event.fieldName());
    }
};

pub const EntityTraitInstance = struct {
    vtable: *const EntityTraitVTable,
    ctx: *anyopaque,
    identifier: []const u8,
};

pub fn EntityTrait(comptime State: type, comptime config: EntityTraitConfig(State)) type {
    return struct {
        pub const identifier = config.identifier;
        pub const tags = config.tags;
        pub const Component = config.component;
        pub const TraitState = State;

        pub const vtable = blk: {
            var vt = buildVTable(State, config);
            vt.destroyFn = &struct {
                fn destroy(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                    const state: *State = @ptrCast(@alignCast(ctx));
                    allocator.destroy(state);
                }
            }.destroy;
            break :blk vt;
        };

        pub fn create(allocator: std.mem.Allocator, initial: State) !EntityTraitInstance {
            const state = try allocator.create(State);
            state.* = initial;
            return .{
                .vtable = &vtable,
                .ctx = @ptrCast(state),
                .identifier = identifier,
            };
        }

        pub fn destroy(instance: EntityTraitInstance, allocator: std.mem.Allocator) void {
            const state: *State = @ptrCast(@alignCast(instance.ctx));
            allocator.destroy(state);
        }

        pub fn appliesTo(entity_type: *const EntityType) bool {
            for (tags) |tag| {
                if (!entity_type.hasTag(tag)) return false;
            }
            if (Component) |C| {
                if (!entity_type.hasComponent(C)) return false;
            }
            return true;
        }
    };
}

fn wrapFn(comptime _: type, comptime event: Event, comptime f: anytype) Event.VTableFnType(event) {
    return switch (event) {
        .Attach, .Detach, .Tick, .Spawn, .Despawn, .Death => &struct {
            fn call(ctx: *anyopaque, entity: *Entity) void {
                f(@ptrCast(@alignCast(ctx)), entity);
            }
        }.call,
        .Damage => &struct {
            fn call(ctx: *anyopaque, entity: *Entity, amount: f32) void {
                f(@ptrCast(@alignCast(ctx)), entity, amount);
            }
        }.call,
        .Interact => &struct {
            fn call(ctx: *anyopaque, entity: *Entity, player: *Player) bool {
                return f(@ptrCast(@alignCast(ctx)), entity, player);
            }
        }.call,
        .ContainerUpdate => &struct {
            fn call(ctx: *anyopaque, entity: *Entity, container: *Container) void {
                f(@ptrCast(@alignCast(ctx)), entity, container);
            }
        }.call,
        .Serialize => &struct {
            fn call(ctx: *anyopaque, nbt: *CompoundTag) void {
                f(@ptrCast(@alignCast(ctx)), nbt);
            }
        }.call,
        .Deserialize => &struct {
            fn call(ctx: *anyopaque, nbt: *const CompoundTag) void {
                f(@ptrCast(@alignCast(ctx)), nbt);
            }
        }.call,
    };
}

fn buildVTable(comptime State: type, comptime config: EntityTraitConfig(State)) EntityTraitVTable {
    var vt = EntityTraitVTable{};
    const fields = @typeInfo(EntityTraitConfig(State)).@"struct".fields;
    inline for (fields) |field| {
        if (comptime eventFromFieldName(field.name)) |event| {
            if (@field(config, field.name)) |f| {
                @field(vt, event.fieldName()) = wrapFn(State, event, f);
            }
        }
    }
    return vt;
}

fn eventFromFieldName(comptime name: []const u8) ?Event {
    const events = [_]Event{
        .Attach,      .Detach, .Tick,     .Spawn,           .Despawn,
        .Damage,      .Death,  .Interact, .ContainerUpdate, .Serialize,
        .Deserialize,
    };
    inline for (events) |e| {
        if (comptime std.mem.eql(u8, name, e.fieldName())) return e;
    }
    return null;
}

pub fn EntityTraitConfig(comptime State: type) type {
    return struct {
        identifier: []const u8,
        tags: []const []const u8 = &.{},
        component: ?type = null,
        onAttach: ?*const fn (*State, *Entity) void = null,
        onDetach: ?*const fn (*State, *Entity) void = null,
        onTick: ?*const fn (*State, *Entity) void = null,
        onSpawn: ?*const fn (*State, *Entity) void = null,
        onDespawn: ?*const fn (*State, *Entity) void = null,
        onDamage: ?*const fn (*State, *Entity, f32) void = null,
        onDeath: ?*const fn (*State, *Entity) void = null,
        onInteract: ?*const fn (*State, *Entity, *Player) bool = null,
        onContainerUpdate: ?*const fn (*State, *Entity, *Container) void = null,
        onSerialize: ?*const fn (*State, *CompoundTag) void = null,
        onDeserialize: ?*const fn (*State, *const CompoundTag) void = null,
    };
}
