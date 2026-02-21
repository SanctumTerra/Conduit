const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const Vector2f = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vector2f {
        return Vector2f{ .x = x, .y = y };
    }

    pub fn read(stream: *BinaryStream) !Vector2f {
        const x = try stream.readFloat32(.Little);
        const y = try stream.readFloat32(.Little);

        return Vector2f{ .x = x, .y = y };
    }

    pub fn write(stream: *BinaryStream, value: Vector2f) !void {
        try stream.writeFloat32(value.x, .Little);
        try stream.writeFloat32(value.y, .Little);
    }
};
