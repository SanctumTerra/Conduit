const std = @import("std");
const CompoundTag = @import("nbt").CompoundTag;
const Protocol = @import("protocol");
const ItemType = @import("./item-type.zig").ItemType;

var nextNetworkStackId: i32 = 0;

pub const ItemStack = struct {
    item_type: *ItemType,
    stackSize: u16,
    metadata: u32,
    nbt: ?CompoundTag,
    networkStackId: i32,

    pub const Options = struct {
        stackSize: u16 = 1,
        metadata: u32 = 0,
        nbt: ?CompoundTag = null,
    };

    pub fn init(item_type: *ItemType, opts: Options) ItemStack {
        const id = @atomicRmw(i32, &nextNetworkStackId, .Add, 1, .monotonic);
        return .{
            .item_type = item_type,
            .stackSize = opts.stackSize,
            .metadata = opts.metadata,
            .nbt = opts.nbt,
            .networkStackId = id,
        };
    }

    pub fn fromIdentifier(identifier: []const u8, opts: Options) ?ItemStack {
        const item_type = ItemType.get(identifier) orelse return null;
        return init(item_type, opts);
    }

    pub fn deinit(self: *ItemStack, allocator: std.mem.Allocator) void {
        if (self.nbt) |*nbt| nbt.deinit(allocator);
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
