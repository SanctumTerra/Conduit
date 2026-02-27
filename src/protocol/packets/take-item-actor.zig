const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;

pub const TakeItemActorPacket = struct {
    itemEntityRuntimeId: u64,
    takerEntityRuntimeId: u64,

    pub fn serialize(self: *const TakeItemActorPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.TakeItemActor);
        try stream.writeVarLong(self.itemEntityRuntimeId);
        try stream.writeVarLong(self.takerEntityRuntimeId);
        return stream.getBuffer();
    }
};
