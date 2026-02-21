const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const DimensionType = @import("../enums/dimension-type.zig").DimensionType;

pub const LevelChunk = struct {
    const MAX_BLOB_HASHES = 64;

    x: i32,
    z: i32,
    dimension: DimensionType,
    highestSubChunkCount: u16,
    subChunkCount: i32,
    cacheEnabled: bool,
    blobs: []const u64,
    data: []const u8,

    pub fn serialize(self: *LevelChunk, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.LevelChunk);
        try stream.writeZigZag(self.x);
        try stream.writeZigZag(self.z);
        try stream.writeZigZag(@intFromEnum(self.dimension));
        try stream.writeVarInt(@intCast(self.subChunkCount));

        if (self.subChunkCount == -2) {
            try stream.writeUint16(self.highestSubChunkCount, .Little);
        }

        try stream.writeBool(self.cacheEnabled);

        if (self.cacheEnabled) {
            if (self.blobs.len == 0) {
                return error.BlobsRequiredWhenCacheEnabled;
            }
            try stream.writeVarInt(@intCast(self.blobs.len));
            for (self.blobs) |hash| {
                try stream.writeUint64(hash, .Little);
            }
        }

        try stream.writeVarInt(@intCast(self.data.len));
        try stream.write(self.data);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !LevelChunk {
        _ = try stream.readVarInt();
        const x = try stream.readZigZag();
        const z = try stream.readZigZag();
        const dimension_raw = try stream.readZigZag();
        const dimension: DimensionType = @enumFromInt(dimension_raw);

        var subChunkCount = try stream.readVarInt();
        if (subChunkCount == 4_294_967_294) {
            subChunkCount = -2;
        }

        var highestSubChunkCount: u16 = 0;
        if (subChunkCount == -2) {
            highestSubChunkCount = try stream.readUint16(.Little);
        }

        const cacheEnabled = try stream.readBool();

        var blobs: []const u64 = &[_]u64{};
        if (cacheEnabled) {
            const blobCount = try stream.readVarInt();
            if (blobCount > MAX_BLOB_HASHES) {
                return error.TooManyBlobHashes;
            }

            const blob_array = try stream.allocator.alloc(u64, @intCast(blobCount));
            for (0..@intCast(blobCount)) |i| {
                blob_array[i] = try stream.readUint64(.Little);
            }
            blobs = blob_array;
        }

        const dataLength = try stream.readVarInt();
        const data = stream.read(@intCast(dataLength));

        return LevelChunk{
            .x = x,
            .z = z,
            .dimension = dimension,
            .highestSubChunkCount = highestSubChunkCount,
            .subChunkCount = subChunkCount,
            .cacheEnabled = cacheEnabled,
            .blobs = blobs,
            .data = data,
        };
    }
};
