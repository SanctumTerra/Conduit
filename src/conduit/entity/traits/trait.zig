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
        pub const entities = config.entities;
        pub const tags = config.tags;
        pub const components = config.components;
        pub const default_state: ?State = config.default_state;
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

        fn defaultFactory(allocator: std.mem.Allocator) !EntityTraitInstance {
            return create(allocator, default_state orelse @compileError("default_state required for global entity trait registration"));
        }

        pub fn register() !void {
            if (entities.len > 0) {
                if (default_state == null) @compileError("default_state required for global entity trait registration");
                try registerTraitForEntities(entities, &defaultFactory);
            }
        }

        pub fn destroy(instance: EntityTraitInstance, allocator: std.mem.Allocator) void {
            const state: *State = @ptrCast(@alignCast(instance.ctx));
            allocator.destroy(state);
        }

        pub fn appliesTo(entity_type: *const EntityType) bool {
            for (tags) |tag| {
                if (!entity_type.hasTag(tag)) return false;
            }
            for (components) |comp| {
                if (!entity_type.hasComponent(comp)) return false;
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
        entities: []const []const u8 = &.{},
        tags: []const []const u8 = &.{},
        components: []const []const u8 = &.{},
        default_state: ?State = null,
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

pub const EntityTraitFactory = *const fn (std.mem.Allocator) error{OutOfMemory}!EntityTraitInstance;

const FactoryList = std.ArrayListUnmanaged(EntityTraitFactory);

var entity_trait_registry: std.StringHashMapUnmanaged(FactoryList) = .{};
var registry_allocator: std.mem.Allocator = undefined;
var registry_initialized: bool = false;

pub fn initEntityTraitRegistry(allocator: std.mem.Allocator) void {
    registry_allocator = allocator;
    entity_trait_registry = .{};
    registry_initialized = true;
}

pub fn deinitEntityTraitRegistry() void {
    if (!registry_initialized) return;
    var iter = entity_trait_registry.valueIterator();
    while (iter.next()) |list| {
        list.deinit(registry_allocator);
    }
    entity_trait_registry.deinit(registry_allocator);
    registry_initialized = false;
}

pub fn registerTraitForEntities(comptime entities: []const []const u8, factory: EntityTraitFactory) !void {
    inline for (entities) |entity_id| {
        const gop = try entity_trait_registry.getOrPut(registry_allocator, entity_id);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(registry_allocator, factory);
    }
}

pub fn applyGlobalTraits(allocator: std.mem.Allocator, entity: *Entity) !void {
    if (!registry_initialized) return;
    const factories = entity_trait_registry.get(entity.entity_type.identifier) orelse return;
    for (factories.items) |factory| {
        const instance = try factory(allocator);
        try entity.addTrait(instance);
    }
}
