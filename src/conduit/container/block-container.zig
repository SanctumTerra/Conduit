const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Container = @import("./container.zig").Container;
const ItemStack = @import("../items/item-stack.zig").ItemStack;
const Player = @import("../player/player.zig").Player;

// TODO: Add Block reference once Block struct is implemented
pub const BlockContainer = struct {
    base: Container,

    pub fn init(allocator: std.mem.Allocator, container_type: Protocol.ContainerType, size: u32) !BlockContainer {
        return .{
            .base = try Container.init(allocator, container_type, size),
        };
    }

    pub fn deinit(self: *BlockContainer) void {
        self.base.deinit();
    }

    pub fn setItem(self: *BlockContainer, slot: u32, item: ItemStack) void {
        self.base.setItem(slot, item);
    }

    pub fn getItem(self: *const BlockContainer, slot: u32) ?*const ItemStack {
        return self.base.getItem(slot);
    }

    pub fn clearSlot(self: *BlockContainer, slot: u32) void {
        self.base.clearSlot(slot);
    }

    pub fn clear(self: *BlockContainer) void {
        self.base.clear();
    }

    pub fn update(self: *BlockContainer) void {
        self.base.update();
        // TODO: call onContainerUpdate for block traits once Block is implemented
    }

    pub fn show(self: *BlockContainer, player: *Player) Protocol.ContainerId {
        const id = self.base.show(player);
        if (id == .None) return .None;

        var stream = BinaryStream.init(self.base.allocator, null, null);
        defer stream.deinit();

        // TODO: use actual block position once Block struct is available
        const packet = Protocol.ContainerOpenPacket{
            .identifier = id,
            .container_type = self.base.container_type,
            .position = Protocol.BlockPosition{ .x = 0, .y = 0, .z = 0 },
            .unique_id = if (self.base.container_type == .Container) -1 else player.entity.runtime_id,
        };
        const serialized = packet.serialize(&stream) catch return id;
        player.network.sendPacket(player.connection, serialized) catch {};

        self.update();
        return id;
    }
};
