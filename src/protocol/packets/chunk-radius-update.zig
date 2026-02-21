const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const ChunkRadiusUpdate = struct {
    radius: i32,

    pub fn serialize(self: *ChunkRadiusUpdate, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ChunkRadiusUpdate);
        try stream.writeZigZag(self.radius);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ChunkRadiusUpdate {
        _ = try stream.readVarInt();
        const radius = try stream.readZigZag();

        return ChunkRadiusUpdate{
            .radius = radius,
        };
    }
};
