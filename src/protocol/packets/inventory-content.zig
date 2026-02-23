const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const ContainerId = @import("../enums/container-id.zig").ContainerId;
const FullContainerName = @import("../root.zig").FullContainerName;
const NetworkItemStackDescriptor = @import("../root.zig").NetworkItemStackDescriptor;

pub const InventoryContentPacket = struct {
    containerId: ContainerId,
    items: []const NetworkItemStackDescriptor,
    fullContainerName: FullContainerName,
    storageItem: NetworkItemStackDescriptor,

    pub fn serialize(self: *const InventoryContentPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.InventoryContent);
        try stream.writeVarInt(@as(u32, @bitCast(@as(i32, @intFromEnum(self.containerId)))));
        try stream.writeVarInt(@intCast(self.items.len));
        for (self.items) |item| {
            try NetworkItemStackDescriptor.write(stream, item, stream.allocator);
        }
        try FullContainerName.write(stream, self.fullContainerName);
        try NetworkItemStackDescriptor.write(stream, self.storageItem, stream.allocator);
        return stream.getBuffer();
    }
};
