const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NetworkItemInstanceDescriptor = @import("network-item-instance-descriptor.zig").NetworkItemInstanceDescriptor;

pub const CreativeItem = struct {
    itemIndex: u32,
    itemInstance: NetworkItemInstanceDescriptor,
    groupIndex: u32,

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) ![]CreativeItem {
        const amount = try stream.readVarInt();
        const items = try allocator.alloc(CreativeItem, amount);
        for (0..amount) |i| {
            const itemIndex = try stream.readVarInt();
            const itemInstance = try NetworkItemInstanceDescriptor.read(stream, allocator);
            const groupIndex = try stream.readVarInt();
            items[i] = .{ .itemIndex = itemIndex, .itemInstance = itemInstance, .groupIndex = groupIndex };
        }
        return items;
    }

    pub fn write(stream: *BinaryStream, values: []const CreativeItem, allocator: std.mem.Allocator) !void {
        try stream.writeVarInt(@intCast(values.len));
        for (values) |item| {
            try stream.writeVarInt(item.itemIndex);
            try NetworkItemInstanceDescriptor.write(stream, item.itemInstance, allocator);
            try stream.writeVarInt(item.groupIndex);
        }
    }
};
