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

        pub fn create(allocator: std.mem.Allocator, initial: State) !BlockTraitInstance {
            const state = try allocator.create(State);
            state.* = initial;
            return .{
                .vtable = &vtable,
                .ctx = @ptrCast(state),
                .identifier = identifier,
            };
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
