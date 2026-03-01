const std = @import("std");
const Block = @import("../block.zig").Block;
const BlockType = @import("../block-type.zig").BlockType;
const Player = @import("../../../player/player.zig").Player;
const CompoundTag = @import("nbt").CompoundTag;

pub const Event = enum {
    Attach,
    Detach,
    Tick,
    Place,
    Break,
    Interact,
    Update,
    Serialize,
    Deserialize,

    pub fn VTableFnType(comptime event: Event) type {
        return switch (event) {
            .Attach, .Detach, .Tick, .Update => *const fn (*anyopaque, *Block) void,
            .Place => *const fn (*anyopaque, *Block, *Player) bool,
            .Break => *const fn (*anyopaque, *Block, ?*Player) bool,
            .Interact => *const fn (*anyopaque, *Block, *Player) bool,
            .Serialize => *const fn (*anyopaque, *CompoundTag) void,
            .Deserialize => *const fn (*anyopaque, *const CompoundTag) void,
        };
    }

    pub fn ReturnType(comptime event: Event) type {
        return switch (event) {
            .Place, .Break, .Interact => bool,
            else => void,
        };
    }

    pub fn fieldName(comptime event: Event) []const u8 {
        return switch (event) {
            .Attach => "onAttach",
            .Detach => "onDetach",
            .Tick => "onTick",
            .Place => "onPlace",
            .Break => "onBreak",
            .Interact => "onInteract",
            .Update => "onUpdate",
            .Serialize => "onSerialize",
            .Deserialize => "onDeserialize",
        };
    }
};

pub const BlockTraitVTable = struct {
    onAttach: ?Event.VTableFnType(.Attach) = null,
    onDetach: ?Event.VTableFnType(.Detach) = null,
    onTick: ?Event.VTableFnType(.Tick) = null,
    onPlace: ?Event.VTableFnType(.Place) = null,
    onBreak: ?Event.VTableFnType(.Break) = null,
    onInteract: ?Event.VTableFnType(.Interact) = null,
    onUpdate: ?Event.VTableFnType(.Update) = null,
    onSerialize: ?Event.VTableFnType(.Serialize) = null,
    onDeserialize: ?Event.VTableFnType(.Deserialize) = null,
    destroyFn: ?*const fn (*anyopaque, std.mem.Allocator) void = null,

    pub fn get(self: *const BlockTraitVTable, comptime event: Event) ?Event.VTableFnType(event) {
        return @field(self, event.fieldName());
    }
};

pub const BlockTraitInstance = struct {
    vtable: *const BlockTraitVTable,
    ctx: *anyopaque,
    identifier: []const u8,
};

pub fn BlockTrait(comptime State: type, comptime config: BlockTraitConfig(State)) type {
    return struct {
        pub const identifier = config.identifier;
        pub const blocks = config.blocks;
        pub const TraitState = State;
        pub const default_state: State = .{};

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

        pub fn create(allocator: std.mem.Allocator, initial: State) !BlockTraitInstance {
            const state = try allocator.create(State);
            state.* = initial;
            return .{
                .vtable = &vtable,
                .ctx = @ptrCast(state),
                .identifier = identifier,
            };
        }

        fn defaultFactory(allocator: std.mem.Allocator) !BlockTraitInstance {
            return create(allocator, default_state);
        }

        pub fn register() !void {
            if (blocks.len > 0) {
                try registerTraitForBlocks(blocks, &defaultFactory);
            }
            try registerTraitById(identifier, &defaultFactory);
        }

        pub fn registerForState(state_key: []const u8) !void {
            try registerDynamicTrait(state_key, &defaultFactory);
            try registerTraitById(identifier, &defaultFactory);
        }

        pub fn destroy(instance: BlockTraitInstance, allocator: std.mem.Allocator) void {
            const state: *State = @ptrCast(@alignCast(instance.ctx));
            allocator.destroy(state);
        }
    };
}

fn wrapFn(comptime _: type, comptime event: Event, comptime f: anytype) Event.VTableFnType(event) {
    return switch (event) {
        .Attach, .Detach, .Tick, .Update => &struct {
            fn call(ctx: *anyopaque, block: *Block) void {
                f(@ptrCast(@alignCast(ctx)), block);
            }
        }.call,
        .Place => &struct {
            fn call(ctx: *anyopaque, block: *Block, player: *Player) bool {
                return f(@ptrCast(@alignCast(ctx)), block, player);
            }
        }.call,
        .Break => &struct {
            fn call(ctx: *anyopaque, block: *Block, player: ?*Player) bool {
                return f(@ptrCast(@alignCast(ctx)), block, player);
            }
        }.call,
        .Interact => &struct {
            fn call(ctx: *anyopaque, block: *Block, player: *Player) bool {
                return f(@ptrCast(@alignCast(ctx)), block, player);
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

fn buildVTable(comptime State: type, comptime config: BlockTraitConfig(State)) BlockTraitVTable {
    var vt = BlockTraitVTable{};
    const fields = @typeInfo(BlockTraitConfig(State)).@"struct".fields;
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
        .Attach,      .Detach,   .Tick,   .Place,
        .Break,       .Interact, .Update, .Serialize,
        .Deserialize,
    };
    inline for (events) |e| {
        if (comptime std.mem.eql(u8, name, e.fieldName())) return e;
    }
    return null;
}

pub fn BlockTraitConfig(comptime State: type) type {
    return struct {
        identifier: []const u8,
        blocks: []const []const u8 = &.{},
        onAttach: ?*const fn (*State, *Block) void = null,
        onDetach: ?*const fn (*State, *Block) void = null,
        onTick: ?*const fn (*State, *Block) void = null,
        onPlace: ?*const fn (*State, *Block, *Player) bool = null,
        onBreak: ?*const fn (*State, *Block, ?*Player) bool = null,
        onInteract: ?*const fn (*State, *Block, *Player) bool = null,
        onUpdate: ?*const fn (*State, *Block) void = null,
        onSerialize: ?*const fn (*State, *CompoundTag) void = null,
        onDeserialize: ?*const fn (*State, *const CompoundTag) void = null,
    };
}

pub const TraitFactory = *const fn (std.mem.Allocator) error{OutOfMemory}!BlockTraitInstance;
pub const DynamicTraitEntry = struct {
    state_key: []const u8,
    factory: TraitFactory,
};

const FactoryList = std.ArrayListUnmanaged(TraitFactory);

var trait_registry: std.StringHashMapUnmanaged(FactoryList) = .{};
var trait_id_registry: std.StringHashMapUnmanaged(TraitFactory) = .{};
var dynamic_traits: std.ArrayListUnmanaged(DynamicTraitEntry) = .{};
var registry_allocator: std.mem.Allocator = undefined;
var registry_initialized: bool = false;

pub fn initTraitRegistry(allocator: std.mem.Allocator) void {
    registry_allocator = allocator;
    trait_registry = .{};
    trait_id_registry = .{};
    dynamic_traits = .{};
    registry_initialized = true;
}

pub fn deinitTraitRegistry() void {
    if (!registry_initialized) return;
    var iter = trait_registry.valueIterator();
    while (iter.next()) |list| {
        list.deinit(registry_allocator);
    }
    trait_registry.deinit(registry_allocator);
    trait_id_registry.deinit(registry_allocator);
    dynamic_traits.deinit(registry_allocator);
    registry_initialized = false;
}

pub fn registerTraitForBlocks(comptime blocks: []const []const u8, factory: TraitFactory) !void {
    inline for (blocks) |block_id| {
        const gop = try trait_registry.getOrPut(registry_allocator, block_id);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(registry_allocator, factory);
    }
}

pub fn registerDynamicTrait(state_key: []const u8, factory: TraitFactory) !void {
    try dynamic_traits.append(registry_allocator, .{ .state_key = state_key, .factory = factory });
}

pub fn registerTraitById(trait_id: []const u8, factory: TraitFactory) !void {
    try trait_id_registry.put(registry_allocator, trait_id, factory);
}

pub fn getTraitFactory(trait_id: []const u8) ?TraitFactory {
    if (!registry_initialized) return null;
    return trait_id_registry.get(trait_id);
}

const Dimension = @import("../../../world/dimension/dimension.zig").Dimension;

pub fn applyTraitsForBlock(allocator: std.mem.Allocator, dimension: *Dimension, position: @import("protocol").BlockPosition) !void {
    if (!registry_initialized) return;
    var temp = Block.init(allocator, dimension, position);
    const identifier = temp.getIdentifier();
    const perm = temp.getPermutation(0) catch null;

    const static_factories = trait_registry.get(identifier);
    const has_dynamic = perm != null and dynamic_traits.items.len > 0;

    if (static_factories == null and !has_dynamic) return;

    const block = try allocator.create(Block);
    block.* = Block.init(allocator, dimension, position);

    if (static_factories) |factories| {
        for (factories.items) |factory| {
            const instance = try factory(allocator);
            try block.addTrait(instance);
        }
    }

    if (perm) |p| {
        for (dynamic_traits.items) |entry| {
            if (p.state.contains(entry.state_key)) {
                const instance = try entry.factory(allocator);
                try block.addTrait(instance);
            }
        }
    }

    try dimension.storeBlock(block);
}

pub fn applyTraitsFromRegistry(allocator: std.mem.Allocator, block: *Block) !void {
    if (!registry_initialized) return;
    const identifier = block.getIdentifier();
    const perm = block.getPermutation(0) catch null;

    if (trait_registry.get(identifier)) |factories| {
        for (factories.items) |factory| {
            const instance = try factory(allocator);
            try block.addTrait(instance);
        }
    }

    if (perm) |p| {
        for (dynamic_traits.items) |entry| {
            if (p.state.contains(entry.state_key)) {
                const instance = try entry.factory(allocator);
                try block.addTrait(instance);
            }
        }
    }
}

pub fn hasRegisteredTraits(identifier: []const u8) bool {
    if (!registry_initialized) return false;
    return trait_registry.contains(identifier);
}

pub fn hasRegisteredDynamicTraits() bool {
    if (!registry_initialized) return false;
    return dynamic_traits.items.len > 0;
}

pub fn getDynamicTraits() []const DynamicTraitEntry {
    if (!registry_initialized) return &.{};
    return dynamic_traits.items;
}

pub fn hasAnyStaticTraits() bool {
    if (!registry_initialized) return false;
    return trait_registry.count() > 0;
}
