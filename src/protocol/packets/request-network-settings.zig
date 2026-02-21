const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const RequestNetworkSettings = struct {
    protocol: i32,

    pub fn serialize(self: *RequestNetworkSettings, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.RequestNetworkSettings);
        try stream.writeInt32(self.protocol, .Big);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !RequestNetworkSettings {
        _ = try stream.readVarInt();
        const protocol = try stream.readInt32(.Big);
        return RequestNetworkSettings{
            .protocol = protocol,
        };
    }
};
