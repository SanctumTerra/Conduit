const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const ChunkCoords = struct {
    x: i32,
    z: i32,

    pub fn init(x: i32, z: i32) ChunkCoords {
        return ChunkCoords{ .x = x, .z = z };
    }

    pub fn read(stream: *BinaryStream) ![]ChunkCoords {
        const amount = try stream.readInt32(.Little);
        const chunks = try stream.allocator.alloc(ChunkCoords, @intCast(amount));

        for (0..@intCast(amount)) |i| {
            const x = try stream.readZigZag();
            const z = try stream.readZigZag();

            chunks[i] = ChunkCoords{
                .x = x,
                .z = z,
            };
        }

        return chunks;
    }

    pub fn write(stream: *BinaryStream, chunks: []const ChunkCoords) !void {
        try stream.writeInt32(@intCast(chunks.len), .Little);

        for (chunks) |chunk| {
            try stream.writeZigZag(chunk.x);
            try stream.writeZigZag(chunk.z);
        }
    }

    pub fn hash(coords: ChunkCoords) i64 {
        const x: i64 = @as(i64, coords.x) << 32;
        const z: i64 = @as(i64, @as(u32, @bitCast(coords.z)));
        return x | z;
    }

    pub fn unhash(hash_value: i64) ChunkCoords {
        const x: i32 = @intCast(hash_value >> 32);

        const z_bits: u32 = @intCast(hash_value & 0xFFFFFFFF);
        const z: i32 = @bitCast(z_bits);

        return ChunkCoords{ .x = x, .z = z };
    }

    pub fn equals(self: ChunkCoords, other: ChunkCoords) bool {
        return self.x == other.x and self.z == other.z;
    }
};
