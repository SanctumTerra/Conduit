const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;

pub const LevelEvent = enum(i32) {
    ParticlesDestroyBlock = 2001,
    StartRain = 3001,
    StartThunder = 3002,
    StopRain = 3003,
    StopThunder = 3004,
    StartBlockCracking = 3600,
    StopBlockCracking = 3601,
    UpdateBlockCracking = 3602,
    _,
};

pub const LevelEventPacket = struct {
    event: LevelEvent,
    position: Vector3f,
    data: i32,

    pub fn serialize(self: *const LevelEventPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.LevelEvent);
        try stream.writeZigZag(@intFromEnum(self.event));
        try Vector3f.write(stream, self.position);
        try stream.writeZigZag(self.data);
        return stream.getBuffer();
    }
};
