const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;
const ReadWriteOptions = NBT.ReadWriteOptions;
const Protocol = @import("protocol");
const ItemType = @import("./item-type.zig").ItemType;
const trait_mod = @import("./trait.zig");
const ItemStackTraitInstance = trait_mod.ItemStackTraitInstance;
const ItemStackTraitEvent = trait_mod.Event;
const Player = @import("../player/player.zig").Player;
const Entity = @import("../entity/entity.zig").Entity;

var nextNetworkStackId: i32 = 0;

pub const ItemStack = struct {
    allocator: std.mem.Allocator,
    item_type: *ItemType,
    stackSize: u16,
    metadata: u32,
    nbt: ?CompoundTag,
    networkStackId: i32,
    traits: std.ArrayListUnmanaged(ItemStackTraitInstance),

    pub const Options = struct {
        stackSize: u16 = 1,
        metadata: u32 = 0,
        nbt: ?CompoundTag = null,
    };

    pub fn init(allocator: std.mem.Allocator, item_type: *ItemType, opts: Options) ItemStack {
        const id = @atomicRmw(i32, &nextNetworkStackId, .Add, 1, .monotonic);
        return .{
            .allocator = allocator,
            .item_type = item_type,
            .stackSize = opts.stackSize,
            .metadata = opts.metadata,
            .nbt = opts.nbt,
            .networkStackId = id,
            .traits = .{},
        };
    }

    pub fn fromIdentifier(allocator: std.mem.Allocator, identifier: []const u8, opts: Options) ?ItemStack {
        const item_type = ItemType.get(identifier) orelse return null;
        return init(allocator, item_type, opts);
    }

    pub fn cloneWithCount(self: *const ItemStack, allocator: std.mem.Allocator, count: u16) !ItemStack {
        return init(allocator, self.item_type, .{
            .stackSize = count,
            .metadata = self.metadata,
            .nbt = if (self.nbt) |*nbt| try cloneCompound(allocator, nbt) else null,
        });
    }

    pub fn isStackCompatible(self: *const ItemStack, other: *const ItemStack) bool {
        if (self.item_type != other.item_type) return false;
        if (self.metadata != other.metadata) return false;
        return equalOptionalCompound(self.allocator, self.nbt, other.nbt);
    }

    pub fn deinit(self: *ItemStack) void {
        for (self.traits.items) |instance| {
            if (instance.vtable.onDetach) |f| f(instance.ctx, self);
            if (instance.vtable.destroyFn) |f| f(instance.ctx, self.allocator);
        }
        self.traits.deinit(self.allocator);
        if (self.nbt) |*nbt| nbt.deinit(self.allocator);
    }

    pub fn addTrait(self: *ItemStack, instance: ItemStackTraitInstance) !void {
        try self.traits.append(self.allocator, instance);
        if (instance.vtable.onAttach) |f| f(instance.ctx, self);
    }

    pub fn removeTrait(self: *ItemStack, id: []const u8) void {
        for (self.traits.items, 0..) |instance, i| {
            if (std.mem.eql(u8, instance.identifier, id)) {
                if (instance.vtable.onDetach) |f| f(instance.ctx, self);
                if (instance.vtable.destroyFn) |f| f(instance.ctx, self.allocator);
                _ = self.traits.swapRemove(i);
                return;
            }
        }
    }

    pub fn hasTrait(self: *const ItemStack, id: []const u8) bool {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, id)) return true;
        }
        return false;
    }

    pub fn getTrait(self: *const ItemStack, id: []const u8) ?ItemStackTraitInstance {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, id)) return instance;
        }
        return null;
    }

    pub fn getTraitState(self: *const ItemStack, comptime T: type) ?*T.TraitState {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, T.identifier)) {
                return @ptrCast(@alignCast(instance.ctx));
            }
        }
        return null;
    }

    pub fn fireEvent(self: *ItemStack, comptime event: ItemStackTraitEvent, args: anytype) ItemStackTraitEvent.ReturnType(event) {
        for (self.traits.items) |instance| {
            if (instance.vtable.get(event)) |f| {
                const result = @call(.auto, f, .{instance.ctx} ++ args);
                if (ItemStackTraitEvent.ReturnType(event) == bool) {
                    if (!result) return false;
                }
            }
        }
        if (ItemStackTraitEvent.ReturnType(event) == bool) return true;
    }

    pub fn toNetworkStack(self: *const ItemStack) Protocol.NetworkItemStackDescriptor {
        const nbt = self.nbt orelse return .{
            .network = self.item_type.network_id,
            .stackSize = self.stackSize,
            .metadata = self.metadata,
            .itemStackId = self.networkStackId,
            .networkBlockId = 0,
            .extras = null,
        };
        return .{
            .network = self.item_type.network_id,
            .stackSize = self.stackSize,
            .metadata = self.metadata,
            .itemStackId = self.networkStackId,
            .networkBlockId = 0,
            .extras = if (nbt.count() > 0) .{
                .nbt = nbt,
                .canPlaceOn = &.{},
                .canDestroy = &.{},
                .ticking = null,
            } else null,
        };
    }

    pub fn toNetworkInstance(self: *const ItemStack) Protocol.NetworkItemInstanceDescriptor {
        const nbt = self.nbt orelse return .{
            .network = self.item_type.network_id,
            .stackSize = self.stackSize,
            .metadata = self.metadata,
            .networkBlockId = 0,
            .extras = null,
        };
        return .{
            .network = self.item_type.network_id,
            .stackSize = self.stackSize,
            .metadata = self.metadata,
            .networkBlockId = 0,
            .extras = if (nbt.count() > 0) .{
                .nbt = nbt,
                .canPlaceOn = &.{},
                .canDestroy = &.{},
                .ticking = null,
            } else null,
        };
    }
};

fn cloneCompound(allocator: std.mem.Allocator, src: *const CompoundTag) !CompoundTag {
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();
    try CompoundTag.write(&stream, src, ReadWriteOptions.default);
    var read_stream = BinaryStream.init(allocator, stream.getBuffer(), null);
    defer read_stream.deinit();
    return try CompoundTag.read(&read_stream, allocator, ReadWriteOptions.default);
}

fn equalOptionalCompound(allocator: std.mem.Allocator, a: ?CompoundTag, b: ?CompoundTag) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;

    var a_stream = BinaryStream.init(allocator, null, null);
    defer a_stream.deinit();
    CompoundTag.write(&a_stream, &a.?, ReadWriteOptions.default) catch return false;

    var b_stream = BinaryStream.init(allocator, null, null);
    defer b_stream.deinit();
    CompoundTag.write(&b_stream, &b.?, ReadWriteOptions.default) catch return false;

    return std.mem.eql(u8, a_stream.getBuffer(), b_stream.getBuffer());
}
