const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;

pub const BlockEventType = enum(i32) {
    Sound = 0,
    ChangeState = 1,
};

pub const BlockEventPacket = struct {
    position: BlockPosition,
    event_type: BlockEventType,
    data: i32,

    pub fn serialize(self: *const BlockEventPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.BlockEvent);
        try BlockPosition.write(stream, self.position);
        try stream.writeZigZag(@intFromEnum(self.event_type));
        try stream.writeZigZag(self.data);
        return stream.getBuffer();
    }
};
