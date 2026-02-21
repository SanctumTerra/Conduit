const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;
const ChunkCoords = @import("../types/chunk-coords.zig").ChunkCoords;

pub const NetworkChunkPublisherUpdate = struct {
    coordinate: BlockPosition,
    radius: i32,
    savedChunks: []const ChunkCoords,

    pub fn serialize(self: *NetworkChunkPublisherUpdate, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.NetworkChunkPublisherUpdate);
        try BlockPosition.write(stream, self.coordinate);
        try stream.writeVarInt(@intCast(self.radius));
        try ChunkCoords.write(stream, self.savedChunks);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !NetworkChunkPublisherUpdate {
        _ = try stream.readVarInt();
        const coordinate = try BlockPosition.read(stream);
        const radius = try stream.readVarInt();
        const savedChunks = try ChunkCoords.read(stream);

        return NetworkChunkPublisherUpdate{
            .coordinate = coordinate,
            .radius = radius,
            .savedChunks = savedChunks,
        };
    }
};
