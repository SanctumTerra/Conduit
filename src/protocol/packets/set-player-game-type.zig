const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;

pub const SetPlayerGameTypePacket = struct {
    gamemode: i32,

    pub fn serialize(self: *const SetPlayerGameTypePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.SetPlayerGameType);
        try stream.writeZigZag(self.gamemode);
        return stream.getBuffer();
    }
};
