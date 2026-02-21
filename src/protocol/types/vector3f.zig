const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const Vector3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vector3f {
        return Vector3f{ .x = x, .y = y, .z = z };
    }

    pub fn read(stream: *BinaryStream) !Vector3f {
        const x = try stream.readFloat32(.Little);
        const y = try stream.readFloat32(.Little);
        const z = try stream.readFloat32(.Little);

        return Vector3f{ .x = x, .y = y, .z = z };
    }

    pub fn write(stream: *BinaryStream, value: Vector3f) !void {
        try stream.writeFloat32(value.x, .Little);
        try stream.writeFloat32(value.y, .Little);
        try stream.writeFloat32(value.z, .Little);
    }

    pub fn floor(self: Vector3f) Vector3f {
        return Vector3f{
            .x = @floor(self.x),
            .y = @floor(self.y),
            .z = @floor(self.z),
        };
    }

    pub fn distance(self: Vector3f, other: Vector3f) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        const dz = self.z - other.z;
        return @sqrt(dx * dx + dy * dy + dz * dz);
    }

    pub fn subtract(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn divide(self: Vector3f, scalar: f32) Vector3f {
        return Vector3f{
            .x = self.x / scalar,
            .y = self.y / scalar,
            .z = self.z / scalar,
        };
    }

    pub fn add(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn multiply(self: Vector3f, scalar: f32) Vector3f {
        return Vector3f{
            .x = self.x * scalar,
            .y = self.y * scalar,
            .z = self.z * scalar,
        };
    }
};
