const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;

pub const UpdateBlockPacket = struct {
    position: BlockPosition,
    networkBlockId: u32,
    flags: u32 = 0b0011,
    layer: u32 = 0,

    pub fn serialize(self: *const UpdateBlockPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.UpdateBlock);
        try BlockPosition.write(stream, self.position);
        try stream.writeVarInt(self.networkBlockId);
        try stream.writeVarInt(self.flags);
        try stream.writeVarInt(self.layer);
        return stream.getBuffer();
    }
};
