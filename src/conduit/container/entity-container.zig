const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Container = @import("./container.zig").Container;
const ItemStack = @import("../items/item-stack.zig").ItemStack;
const Player = @import("../player/player.zig").Player;

pub const EntityContainer = struct {
    base: Container,
    owner: *Player,

    pub fn init(allocator: std.mem.Allocator, owner: *Player, container_type: Protocol.ContainerType, size: u32) !EntityContainer {
        return .{
            .base = try Container.init(allocator, container_type, size),
            .owner = owner,
        };
    }

    pub fn deinit(self: *EntityContainer) void {
        self.base.deinit();
    }

    pub fn isOwnedBy(self: *const EntityContainer, player: *const Player) bool {
        return self.owner == player;
    }

    pub fn setItem(self: *EntityContainer, slot: u32, item: ItemStack) void {
        self.base.setItem(slot, item);
    }

    pub fn getItem(self: *const EntityContainer, slot: u32) ?*const ItemStack {
        return self.base.getItem(slot);
    }

    pub fn clearSlot(self: *EntityContainer, slot: u32) void {
        self.base.clearSlot(slot);
        self.sendOwnerSlotUpdate(slot);
    }

    pub fn clear(self: *EntityContainer) void {
        self.base.clear();
        self.sendOwnerContentUpdate();
    }

    pub fn addItem(self: *EntityContainer, item: ItemStack) bool {
        const result = self.base.addItem(item);
        self.sendOwnerContentUpdate();
        return result;
    }

    pub fn updateSlot(self: *EntityContainer, slot: u32) void {
        self.base.updateSlot(slot);
        self.sendOwnerSlotUpdate(slot);
    }

    pub fn update(self: *EntityContainer) void {
        self.base.update();
        self.sendOwnerContentUpdate();
    }

    pub fn show(self: *EntityContainer, player: *Player) Protocol.ContainerId {
        const owned = self.isOwnedBy(player);

        if (owned) {
            if (player.opened_container) |opened| opened.close(player, true);
            player.opened_container = &self.base;
        }

        const id: Protocol.ContainerId = if (owned) .Inventory else blk: {
            const dynamic_id = self.base.show(player);
            if (dynamic_id == .None) return .None;
            break :blk dynamic_id;
        };

        var stream = BinaryStream.init(self.base.allocator, null, null);
        defer stream.deinit();

        const packet = Protocol.ContainerOpenPacket{
            .identifier = id,
            .container_type = if (owned) .Inventory else self.base.container_type,
            .position = Protocol.BlockPosition{
                .x = @intFromFloat(self.owner.entity.position.x),
                .y = @intFromFloat(self.owner.entity.position.y),
                .z = @intFromFloat(self.owner.entity.position.z),
            },
            .unique_id = self.owner.entity.unique_id,
        };
        const serialized = packet.serialize(&stream) catch return id;
        player.network.sendPacket(player.connection, serialized) catch {};

        if (owned) {
            self.sendOwnerContentUpdate();
        } else {
            self.base.update();
        }

        return id;
    }

    pub fn sendContentUpdate(self: *EntityContainer) void {
        self.sendOwnerContentUpdate();
    }

    fn sendOwnerSlotUpdate(self: *EntityContainer, slot: u32) void {
        const item_stack = if (slot < self.base.storage.len) self.base.storage[slot] else null;
        const network_item = if (item_stack) |item| item.toNetworkStack() else Protocol.NetworkItemStackDescriptor{
            .network = 0,
            .stackSize = null,
            .metadata = null,
            .itemStackId = null,
            .networkBlockId = null,
            .extras = null,
        };

        var stream = BinaryStream.init(self.base.allocator, null, null);
        defer stream.deinit();

        const packet = Protocol.InventorySlotPacket{
            .containerId = self.base.identifier orelse .None,
            .slot = slot,
            .fullContainerName = .{ .identifier = .AnvilInput, .dynamicIdentifier = 0 },
            .storageItem = .{ .network = 0, .stackSize = null, .metadata = null, .itemStackId = null, .networkBlockId = null, .extras = null },
            .item = network_item,
        };
        const serialized = packet.serialize(&stream) catch return;
        self.owner.network.sendPacket(self.owner.connection, serialized) catch {};
    }

    pub fn sendOwnerContentUpdate(self: *EntityContainer) void {
        const items = self.base.allocator.alloc(Protocol.NetworkItemStackDescriptor, self.base.storage.len) catch return;
        defer self.base.allocator.free(items);

        for (self.base.storage, 0..) |slot, i| {
            items[i] = if (slot) |item| item.toNetworkStack() else Protocol.NetworkItemStackDescriptor{
                .network = 0,
                .stackSize = null,
                .metadata = null,
                .itemStackId = null,
                .networkBlockId = null,
                .extras = null,
            };
        }

        const id = self.base.identifier orelse .None;

        var stream = BinaryStream.init(self.base.allocator, null, null);
        defer stream.deinit();

        const packet = Protocol.InventoryContentPacket{
            .containerId = id,
            .items = items,
            .fullContainerName = .{ .identifier = .AnvilInput, .dynamicIdentifier = 0 },
            .storageItem = .{ .network = 0, .stackSize = null, .metadata = null, .itemStackId = null, .networkBlockId = null, .extras = null },
        };
        const serialized = packet.serialize(&stream) catch return;
        self.owner.network.sendPacket(self.owner.connection, serialized) catch {};
    }
};
