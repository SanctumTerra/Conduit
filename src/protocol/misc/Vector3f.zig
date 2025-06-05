const std = @import("std");
const BinaryStream = @import("BinaryStream");

pub const Vector3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vector3f {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn serialize(self: *Vector3f) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeFloat32(self.x, .Little);
        stream.writeFloat32(self.y, .Little);
        stream.writeFloat32(self.z, .Little);
        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for vector3f");
    }

    pub fn deserialize(data: []const u8) Vector3f {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        const x = stream.readFloat32(.Little);
        const y = stream.readFloat32(.Little);
        const z = stream.readFloat32(.Little);
        return .{ .x = x, .y = y, .z = z };
    }
};
