const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const ClientCacheStatus = struct {
    enabled: bool,

    pub fn serialize(self: *ClientCacheStatus, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ClientCacheStatus);
        try stream.writeBool(self.enabled);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ClientCacheStatus {
        _ = try stream.readVarInt();
        const enabled = try stream.readBool();

        return ClientCacheStatus{
            .enabled = enabled,
        };
    }
};
