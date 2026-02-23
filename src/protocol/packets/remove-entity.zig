const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;

pub const RemoveEntityPacket = struct {
    uniqueEntityId: i64,

    pub fn serialize(self: *const RemoveEntityPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.RemoveActor);
        try stream.writeZigZong(self.uniqueEntityId);
        return stream.getBuffer();
    }
};
