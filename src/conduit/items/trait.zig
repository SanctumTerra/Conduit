const std = @import("std");
const ItemStack = @import("./item-stack.zig").ItemStack;
const ItemType = @import("./item-type.zig").ItemType;
const CompoundTag = @import("nbt").CompoundTag;
const Player = @import("../player/player.zig").Player;
const Entity = @import("../entity/entity.zig").Entity;

pub const Event = enum {
    Attach,
    Detach,
    Use,
    StopUse,
    StartUseOn,
    StopUseOn,
    Attack,
    Break,
    Consume,
    Serialize,
    Deserialize,

    pub fn VTableFnType(comptime event: Event) type {
        return switch (event) {
            .Attach, .Detach, .Break, .Consume => *const fn (*anyopaque, *ItemStack) void,
            .Use => *const fn (*anyopaque, *ItemStack, *Player) bool,
            .StopUse => *const fn (*anyopaque, *ItemStack, *Player) void,
            .StartUseOn, .StopUseOn => *const fn (*anyopaque, *ItemStack, *Player) void,
            .Attack => *const fn (*anyopaque, *ItemStack, *Entity) void,
            .Serialize => *const fn (*anyopaque, *CompoundTag) void,
            .Deserialize => *const fn (*anyopaque, *const CompoundTag) void,
        };
    }

    pub fn ReturnType(comptime event: Event) type {
        return switch (event) {
            .Use => bool,
            else => void,
        };
    }

    pub fn fieldName(comptime event: Event) []const u8 {
        return switch (event) {
            .Attach => "onAttach",
            .Detach => "onDetach",
            .Use => "onUse",
            .StopUse => "onStopUse",
            .StartUseOn => "onStartUseOn",
            .StopUseOn => "onStopUseOn",
            .Attack => "onAttack",
            .Break => "onBreak",
            .Consume => "onConsume",
            .Serialize => "onSerialize",
            .Deserialize => "onDeserialize",
        };
    }
};

pub const ItemStackTraitVTable = struct {
    onAttach: ?Event.VTableFnType(.Attach) = null,
    onDetach: ?Event.VTableFnType(.Detach) = null,
    onUse: ?Event.VTableFnType(.Use) = null,
    onStopUse: ?Event.VTableFnType(.StopUse) = null,
    onStartUseOn: ?Event.VTableFnType(.StartUseOn) = null,
    onStopUseOn: ?Event.VTableFnType(.StopUseOn) = null,
    onAttack: ?Event.VTableFnType(.Attack) = null,
    onBreak: ?Event.VTableFnType(.Break) = null,
    onConsume: ?Event.VTableFnType(.Consume) = null,
    onSerialize: ?Event.VTableFnType(.Serialize) = null,
    onDeserialize: ?Event.VTableFnType(.Deserialize) = null,
    destroyFn: ?*const fn (*anyopaque, std.mem.Allocator) void = null,

    pub fn get(self: *const ItemStackTraitVTable, comptime event: Event) ?Event.VTableFnType(event) {
        return @field(self, event.fieldName());
    }
};

pub const ItemStackTraitInstance = struct {
    vtable: *const ItemStackTraitVTable,
    ctx: *anyopaque,
    identifier: []const u8,
};

pub fn ItemStackTrait(comptime State: type, comptime config: ItemStackTraitConfig(State)) type {
    return struct {
        pub const identifier = config.identifier;
        pub const tags = config.tags;
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

        pub fn create(allocator: std.mem.Allocator, initial: State) !ItemStackTraitInstance {
            const state = try allocator.create(State);
            state.* = initial;
            return .{
                .vtable = &vtable,
                .ctx = @ptrCast(state),
                .identifier = identifier,
            };
        }

        pub fn destroy(instance: ItemStackTraitInstance, allocator: std.mem.Allocator) void {
            const state: *State = @ptrCast(@alignCast(instance.ctx));
            allocator.destroy(state);
        }

        pub fn appliesTo(item_type: *const ItemType) bool {
            for (tags) |tag| {
                if (!item_type.hasTag(tag)) return false;
            }
            return true;
        }
    };
}

fn wrapFn(comptime _: type, comptime event: Event, comptime f: anytype) Event.VTableFnType(event) {
    return switch (event) {
        .Attach, .Detach, .Break, .Consume => &struct {
            fn call(ctx: *anyopaque, stack: *ItemStack) void {
                f(@ptrCast(@alignCast(ctx)), stack);
            }
        }.call,
        .Use => &struct {
            fn call(ctx: *anyopaque, stack: *ItemStack, player: *Player) bool {
                return f(@ptrCast(@alignCast(ctx)), stack, player);
            }
        }.call,
        .StopUse, .StartUseOn, .StopUseOn => &struct {
            fn call(ctx: *anyopaque, stack: *ItemStack, player: *Player) void {
                f(@ptrCast(@alignCast(ctx)), stack, player);
            }
        }.call,
        .Attack => &struct {
            fn call(ctx: *anyopaque, stack: *ItemStack, entity: *Entity) void {
                f(@ptrCast(@alignCast(ctx)), stack, entity);
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

fn buildVTable(comptime State: type, comptime config: ItemStackTraitConfig(State)) ItemStackTraitVTable {
    var vt = ItemStackTraitVTable{};
    const fields = @typeInfo(ItemStackTraitConfig(State)).@"struct".fields;
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
        .Attach,     .Detach,    .Use,         .StopUse,
        .StartUseOn, .StopUseOn, .Attack,      .Break,
        .Consume,    .Serialize, .Deserialize,
    };
    inline for (events) |e| {
        if (comptime std.mem.eql(u8, name, e.fieldName())) return e;
    }
    return null;
}

pub fn ItemStackTraitConfig(comptime State: type) type {
    return struct {
        identifier: []const u8,
        tags: []const []const u8 = &.{},
        onAttach: ?*const fn (*State, *ItemStack) void = null,
        onDetach: ?*const fn (*State, *ItemStack) void = null,
        onUse: ?*const fn (*State, *ItemStack, *Player) bool = null,
        onStopUse: ?*const fn (*State, *ItemStack, *Player) void = null,
        onStartUseOn: ?*const fn (*State, *ItemStack, *Player) void = null,
        onStopUseOn: ?*const fn (*State, *ItemStack, *Player) void = null,
        onAttack: ?*const fn (*State, *ItemStack, *Entity) void = null,
        onBreak: ?*const fn (*State, *ItemStack) void = null,
        onConsume: ?*const fn (*State, *ItemStack) void = null,
        onSerialize: ?*const fn (*State, *CompoundTag) void = null,
        onDeserialize: ?*const fn (*State, *const CompoundTag) void = null,
    };
}
