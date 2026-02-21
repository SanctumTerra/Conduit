const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const PlayStatusEnum = @import("../root.zig").PlayStatusEnum;

pub const PlayStatus = struct {
    status: PlayStatusEnum,

    pub fn serialize(self: *PlayStatus, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.PlayStatus);
        try stream.writeInt32(@intFromEnum(self.status), .Big);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !PlayStatus {
        _ = try stream.readVarInt();
        const status: PlayStatusEnum = @enumFromInt(try stream.readInt32(.Big));

        return PlayStatus{
            .status = status,
        };
    }
};
