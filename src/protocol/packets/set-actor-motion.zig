const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;

pub const SetActorMotionPacket = struct {
    runtimeEntityId: u64,
    motion: Vector3f,
    tick: u64 = 0,

    pub fn serialize(self: *const SetActorMotionPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.SetActorMotion);
        try stream.writeVarLong(self.runtimeEntityId);
        try Vector3f.write(stream, self.motion);
        try stream.writeVarLong(self.tick);
        return stream.getBuffer();
    }
};
