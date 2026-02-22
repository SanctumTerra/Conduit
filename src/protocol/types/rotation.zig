const BinaryStream = @import("BinaryStream").BinaryStream;

pub const Rotation = struct {
    pitch: f32,
    yaw: f32,
    headYaw: f32,

    pub fn init(pitch: f32, yaw: f32, headYaw: f32) Rotation {
        return .{ .pitch = pitch, .yaw = yaw, .headYaw = headYaw };
    }

    pub fn read(stream: *BinaryStream) !Rotation {
        const pitch = try stream.readFloat32(.Little);
        const yaw = try stream.readFloat32(.Little);
        const headYaw = try stream.readFloat32(.Little);
        return .{ .pitch = pitch, .yaw = yaw, .headYaw = headYaw };
    }

    pub fn write(stream: *BinaryStream, value: Rotation) !void {
        try stream.writeFloat32(value.pitch, .Little);
        try stream.writeFloat32(value.yaw, .Little);
        try stream.writeFloat32(value.headYaw, .Little);
    }
};
