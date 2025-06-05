const std = @import("std");
const BinaryStream = @import("BinaryStream");

pub const BlockPosition = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn init(x: i32, y: i32, z: i32) BlockPosition {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn serialize(self: *BlockPosition) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeZigZag(self.x);
        stream.writeVarInt(@as(u32, @intCast(self.y)), .Big);
        stream.writeZigZag(self.z);
        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for BlockPosition");
    }

    pub fn deserialize(data: []const u8) BlockPosition {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        const x = stream.readZigZag();
        const y = stream.readVarInt(.Big);
        const z = stream.readZigZag();
        return .{ .x = x, .y = y, .z = z };
    }
};
