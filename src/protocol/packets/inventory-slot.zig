const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const ContainerId = @import("../root.zig").ContainerId;
const FullContainerName = @import("../root.zig").FullContainerName;
const NetworkItemStackDescriptor = @import("../root.zig").NetworkItemStackDescriptor;

pub const InventorySlotPacket = struct {
    containerId: ContainerId,
    slot: u32,
    fullContainerName: FullContainerName,
    storageItem: NetworkItemStackDescriptor,
    item: NetworkItemStackDescriptor,

    pub fn serialize(self: *const InventorySlotPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.InventorySlot);
        try stream.writeVarInt(@as(u32, @bitCast(@as(i32, @intFromEnum(self.containerId)))));
        try stream.writeVarInt(self.slot);
        try FullContainerName.write(stream, self.fullContainerName);
        try NetworkItemStackDescriptor.write(stream, self.storageItem, stream.allocator);
        try NetworkItemStackDescriptor.write(stream, self.item, stream.allocator);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !InventorySlotPacket {
        _ = try stream.readVarInt();
        const containerId: ContainerId = @enumFromInt(@as(i8, @truncate(@as(i32, @bitCast(try stream.readVarInt())))));
        const slot = try stream.readVarInt();
        const fullContainerName = try FullContainerName.read(stream);
        const storageItem = try NetworkItemStackDescriptor.read(stream, stream.allocator);
        const item = try NetworkItemStackDescriptor.read(stream, stream.allocator);
        return .{
            .containerId = containerId,
            .slot = slot,
            .fullContainerName = fullContainerName,
            .storageItem = storageItem,
            .item = item,
        };
    }
};
