const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const RequestChunkRadius = struct {
    radius: i32,
    maxRadius: u8,

    pub fn serialize(self: *RequestChunkRadius, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.RequestChunkRadius);
        try stream.writeZigZag(self.radius);
        try stream.writeUint8(self.maxRadius);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !RequestChunkRadius {
        _ = try stream.readVarInt();
        const radius = try stream.readZigZag();
        const maxRadius = try stream.readUint8();

        return RequestChunkRadius{
            .radius = radius,
            .maxRadius = maxRadius,
        };
    }
};
