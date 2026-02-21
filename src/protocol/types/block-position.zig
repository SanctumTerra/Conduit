const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const BlockPosition = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn init(x: i32, y: i32, z: i32) BlockPosition {
        return BlockPosition{ .x = x, .y = y, .z = z };
    }

    pub fn toVector3f(self: BlockPosition) @import("vector3f.zig").Vector3f {
        return .{
            .x = @floatFromInt(self.x),
            .y = @floatFromInt(self.y),
            .z = @floatFromInt(self.z),
        };
    }

    pub fn read(stream: *BinaryStream) !BlockPosition {
        const x = try stream.readZigZag();
        const raw_y = try stream.readVarInt();
        const z = try stream.readZigZag();

        const y: i32 = if (raw_y > @as(u32, 2_147_483_647))
            @as(i32, @bitCast(raw_y))
        else
            @intCast(raw_y);

        return BlockPosition{ .x = x, .y = y, .z = z };
    }

    pub fn write(stream: *BinaryStream, value: BlockPosition) !void {
        const y: u32 = if (value.y < 0) @intCast(@as(i64, 4_294_967_296) + value.y) else @intCast(value.y);

        try stream.writeZigZag(value.x);
        try stream.writeVarInt(@intCast(y));
        try stream.writeZigZag(value.z);
    }
};
