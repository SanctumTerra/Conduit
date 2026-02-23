const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const CreativeItemCategory = @import("../enums/creative-item-category.zig").CreativeItemCategory;
const NetworkItemInstanceDescriptor = @import("network-item-instance-descriptor.zig").NetworkItemInstanceDescriptor;

pub const CreativeGroup = struct {
    category: CreativeItemCategory,
    name: []const u8,
    icon: NetworkItemInstanceDescriptor,

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) ![]CreativeGroup {
        const amount = try stream.readVarInt();
        const groups = try allocator.alloc(CreativeGroup, amount);
        for (0..amount) |i| {
            const category: CreativeItemCategory = @enumFromInt(try stream.readInt32(.Little));
            const name = try stream.readVarString();
            const icon = try NetworkItemInstanceDescriptor.read(stream, allocator);
            groups[i] = .{ .category = category, .name = name, .icon = icon };
        }
        return groups;
    }

    pub fn write(stream: *BinaryStream, values: []const CreativeGroup, allocator: std.mem.Allocator) !void {
        try stream.writeVarInt(@intCast(values.len));
        for (values) |group| {
            try stream.writeInt32(@intFromEnum(group.category), .Little);
            try stream.writeVarString(group.name);
            try NetworkItemInstanceDescriptor.write(stream, group.icon, allocator);
        }
    }
};
