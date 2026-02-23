const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const CreativeGroup = @import("../root.zig").CreativeGroup;
const CreativeItem = @import("../root.zig").CreativeItem;

pub const CreativeContentPacket = struct {
    groups: []const CreativeGroup,
    items: []const CreativeItem,

    pub fn serialize(self: *const CreativeContentPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.CreativeContent);
        try CreativeGroup.write(stream, self.groups, stream.allocator);
        try CreativeItem.write(stream, self.items, stream.allocator);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !CreativeContentPacket {
        _ = try stream.readVarInt();
        const groups = try CreativeGroup.read(stream, stream.allocator);
        const items = try CreativeItem.read(stream, stream.allocator);
        return .{ .groups = groups, .items = items };
    }
};
