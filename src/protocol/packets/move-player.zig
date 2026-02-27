const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;

pub const MoveMode = enum(u8) {
    Normal = 0,
    Reset = 1,
    Teleport = 2,
    Rotation = 3,
};

pub const MovePlayerPacket = struct {
    runtime_id: u64,
    position: Vector3f,
    pitch: f32,
    yaw: f32,
    head_yaw: f32,
    mode: MoveMode,
    on_ground: bool,
    riding_runtime_id: u64 = 0,
    tick: u64 = 0,

    pub fn serialize(self: *const MovePlayerPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.MovePlayer);
        try stream.writeVarLong(@intCast(self.runtime_id));
        try Vector3f.write(stream, self.position);
        try stream.writeFloat32(self.pitch, .Little);
        try stream.writeFloat32(self.yaw, .Little);
        try stream.writeFloat32(self.head_yaw, .Little);
        try stream.writeUint8(@intFromEnum(self.mode));
        try stream.writeBool(self.on_ground);
        try stream.writeVarLong(@intCast(self.riding_runtime_id));
        if (self.mode == .Teleport) {
            try stream.writeUint32(0, .Little);
            try stream.writeUint32(0, .Little);
        }
        return stream.getBuffer();
    }
};
