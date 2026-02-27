const std = @import("std");
const BlockStorage = @import("./storage/block-storage.zig").BlockStorage;
const BiomeStorage = @import("./storage/biome-storage.zig").BiomeStorage;
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const SubChunk = struct {
    const VERSION: u8 = 9;

    allocator: std.mem.Allocator,
    version: u8,
    index: i8,
    layers: std.ArrayList(BlockStorage),
    biomes: BiomeStorage,

    pub fn init(allocator: std.mem.Allocator, index: i8) !SubChunk {
        return SubChunk{
            .allocator = allocator,
            .version = VERSION,
            .index = index,
            .layers = .{ .items = &.{}, .capacity = 0 },
            .biomes = try BiomeStorage.init(allocator),
        };
    }

    pub fn deinit(self: *SubChunk) void {
        for (self.layers.items) |*layer| layer.deinit();
        self.layers.deinit(self.allocator);
        self.biomes.deinit();
    }

    pub fn isEmpty(self: *const SubChunk) bool {
        for (self.layers.items) |*layer| {
            if (!layer.isEmpty()) return false;
        }
        return true;
    }

    pub fn getLayer(self: *SubChunk, layer: usize) !*BlockStorage {
        while (self.layers.items.len <= layer) {
            try self.layers.append(self.allocator, try BlockStorage.init(self.allocator));
        }
        return &self.layers.items[layer];
    }

    pub fn getState(self: *SubChunk, bx: u8, by: u8, bz: u8, layer: usize) !i32 {
        const storage = try self.getLayer(layer);
        return storage.getState(bx, by, bz);
    }

    pub fn setState(self: *SubChunk, bx: u8, by: u8, bz: u8, state: i32, layer: usize) !void {
        const storage = try self.getLayer(layer);
        try storage.setState(bx, by, bz, state);
    }

    pub fn getBiome(self: *const SubChunk, bx: u8, by: u8, bz: u8) u32 {
        return self.biomes.getBiome(bx, by, bz);
    }

    pub fn setBiome(self: *SubChunk, bx: u8, by: u8, bz: u8, biome: u32) !void {
        try self.biomes.setBiome(bx, by, bz, biome);
    }

    pub fn serialize(self: *const SubChunk, stream: *BinaryStream) !void {
        try stream.writeUint8(self.version);
        try stream.writeUint8(@intCast(self.layers.items.len));
        if (self.version == 9) try stream.writeInt8(self.index);
        for (self.layers.items) |*layer| try layer.serialize(stream);
    }

    pub fn serializePersistence(self: *const SubChunk, stream: *BinaryStream, allocator: std.mem.Allocator) !void {
        try stream.writeUint8(self.version);
        try stream.writeUint8(@intCast(self.layers.items.len));
        if (self.version == 9) try stream.writeInt8(self.index);
        for (self.layers.items) |*layer| try layer.serializePersistence(stream, allocator);
    }

    pub fn deserialize(stream: *BinaryStream, allocator: std.mem.Allocator) !SubChunk {
        const version = try stream.readUint8();
        const count = try stream.readUint8();
        const index: i8 = if (version == 9) try stream.readInt8() else 0;

        var layers = std.ArrayList(BlockStorage){ .items = &.{}, .capacity = 0 };
        errdefer {
            for (layers.items) |*layer| layer.deinit();
            layers.deinit(allocator);
        }
        for (0..count) |_| {
            try layers.append(allocator, try BlockStorage.deserialize(stream, allocator));
        }

        return SubChunk{
            .allocator = allocator,
            .version = version,
            .index = index,
            .layers = layers,
            .biomes = try BiomeStorage.init(allocator),
        };
    }
};
