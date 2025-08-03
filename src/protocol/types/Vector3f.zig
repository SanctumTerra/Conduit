const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;

pub const Vector3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vector3f {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn serialize(self: *Vector3f) []const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeFloat32(self.x, .Little);
        stream.writeFloat32(self.y, .Little);
        stream.writeFloat32(self.z, .Little);
        return stream.getBufferOwned(CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize Vector3f {any}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) Vector3f {
        var stream = BinaryStream.init(CAllocator.get(), data, 0);
        defer stream.deinit();
        const x = stream.readFloat32(.Little);
        const y = stream.readFloat32(.Little);
        const z = stream.readFloat32(.Little);
        return .{ .x = x, .y = y, .z = z };
    }
};
