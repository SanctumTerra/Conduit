const std = @import("std");
const SubChunk = @import("./subchunk.zig").SubChunk;
const BiomeStorage = @import("./storage/biome-storage.zig").BiomeStorage;
const BlockPermutation = @import("../block/block-permutation.zig").BlockPermutation;
const BinaryStream = @import("BinaryStream").BinaryStream;
const DimensionType = @import("protocol").DimensionType;

pub const MAX_SUBCHUNKS: usize = 24;
pub const OVERWORLD_OFFSET: usize = 4;

pub fn yOffset(dimension: DimensionType) usize {
    return if (dimension == .Overworld) OVERWORLD_OFFSET else 0;
}

pub const Chunk = struct {
    allocator: std.mem.Allocator,
    x: i32,
    z: i32,
    dimension: DimensionType,
    subchunks: [MAX_SUBCHUNKS]?*SubChunk,
    dirty: bool,
    cache: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, x: i32, z: i32, dimension: DimensionType) Chunk {
        return Chunk{
            .allocator = allocator,
            .x = x,
            .z = z,
            .dimension = dimension,
            .subchunks = [_]?*SubChunk{null} ** MAX_SUBCHUNKS,
            .dirty = false,
            .cache = null,
        };
    }

    pub fn deinit(self: *Chunk) void {
        for (&self.subchunks) |*slot| {
            if (slot.*) |sc| {
                sc.deinit();
                self.allocator.destroy(sc);
                slot.* = null;
            }
        }
        if (self.cache) |c| self.allocator.free(c);
    }

    fn resolveIndex(self: *const Chunk, y: i32) ?usize {
        const offset: i32 = @intCast(yOffset(self.dimension));
        const idx = offset + (y >> 4);
        if (idx < 0 or idx >= MAX_SUBCHUNKS) return null;
        return @intCast(idx);
    }

    fn getOrCreateSubChunk(self: *Chunk, idx: usize) !*SubChunk {
        if (self.subchunks[idx]) |sc| return sc;
        const offset = yOffset(self.dimension);
        const sc = try self.allocator.create(SubChunk);
        sc.* = try SubChunk.init(self.allocator, @intCast(@as(i32, @intCast(idx)) - @as(i32, @intCast(offset))));
        self.subchunks[idx] = sc;
        return sc;
    }

    pub fn getPermutation(self: *Chunk, x: i32, y: i32, z: i32, layer: usize) !*BlockPermutation {
        const idx = self.resolveIndex(y) orelse return error.OutOfBounds;
        const sc = try self.getOrCreateSubChunk(idx);
        const state = try sc.getState(@intCast(x & 0xf), @intCast(@as(u32, @bitCast(y)) & 0xf), @intCast(z & 0xf), layer);
        return BlockPermutation.getByNetworkId(state) orelse return error.UnknownPermutation;
    }

    pub fn setPermutation(self: *Chunk, x: i32, y: i32, z: i32, permutation: *BlockPermutation, layer: usize) !void {
        const idx = self.resolveIndex(y) orelse return error.OutOfBounds;
        const sc = try self.getOrCreateSubChunk(idx);
        try sc.setState(@intCast(x & 0xf), @intCast(@as(u32, @bitCast(y)) & 0xf), @intCast(z & 0xf), permutation.network_id, layer);
        self.dirty = true;
        self.invalidateCache();
    }

    pub fn getSubChunkSendCount(self: *const Chunk) usize {
        var count: usize = MAX_SUBCHUNKS;
        while (count > 0) : (count -= 1) {
            if (self.subchunks[count - 1]) |sc| {
                if (!sc.isEmpty()) return count;
            }
        }
        return 0;
    }

    fn invalidateCache(self: *Chunk) void {
        if (self.cache) |c| {
            self.allocator.free(c);
            self.cache = null;
        }
    }

    pub fn serialize(self: *Chunk, stream: *BinaryStream) !void {
        const send_count = self.getSubChunkSendCount();
        for (0..send_count) |i| {
            if (self.subchunks[i]) |sc| {
                try sc.serialize(stream);
            } else {
                const offset = yOffset(self.dimension);
                try stream.writeUint8(9);
                try stream.writeUint8(0);
                try stream.writeInt8(@intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset))));
            }
        }
        for (0..send_count) |i| {
            if (self.subchunks[i]) |sc| {
                try sc.biomes.serialize(stream);
            }
        }
        try stream.writeUint8(0);
    }
};
