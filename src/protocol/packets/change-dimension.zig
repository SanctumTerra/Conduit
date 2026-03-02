const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const DimensionType = @import("../enums/dimension-type.zig").DimensionType;
const Vector3f = @import("../types/vector3f.zig").Vector3f;

pub const ChangeDimensionPacket = struct {
    dimension: DimensionType,
    position: Vector3f,
    respawn: bool,

    pub fn serialize(self: *ChangeDimensionPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ChangeDimension);
        try stream.writeZigZag(@intFromEnum(self.dimension));
        try Vector3f.write(stream, self.position);
        try stream.writeBool(self.respawn);
        return stream.getBuffer();
    }
};
