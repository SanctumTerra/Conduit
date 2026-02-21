const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const BiomeStorage = struct {
    const MAX_X = 16;
    const MAX_Y = 16;
    const MAX_Z = 16;
    const MAX_SIZE = 16 * 16 * 16;

    allocator: std.mem.Allocator,
    size: [3]usize,
    palette: std.ArrayList(u32),
    biomes: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) !BiomeStorage {
        var palette = std.ArrayList(u32){
            .items = &[_]u32{},
            .capacity = 0,
        };
        try palette.append(allocator, 0);

        var biomes = std.ArrayList(u32){
            .items = &[_]u32{},
            .capacity = 0,
        };
        try biomes.appendNTimes(allocator, 0, MAX_SIZE);

        return BiomeStorage{
            .allocator = allocator,
            .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
            .palette = palette,
            .biomes = biomes,
        };
    }

    pub fn deinit(self: *BiomeStorage) void {
        self.palette.deinit(self.allocator);
        self.biomes.deinit(self.allocator);
    }

    pub fn isEmpty(self: *const BiomeStorage) bool {
        return self.palette.items.len == 1 and self.palette.items[0] == 0;
    }

    pub fn getBiome(self: *const BiomeStorage, bx: u8, by: u8, bz: u8) u32 {
        const index = self.getIndex(bx, by, bz);
        const palette_index = self.biomes.items[index];
        return self.palette.items[palette_index];
    }

    pub fn setBiome(self: *BiomeStorage, bx: u8, by: u8, bz: u8, biome: u32) !void {
        var palette_index: u32 = 0;
        var found = false;
        for (self.palette.items, 0..) |pal_biome, i| {
            if (pal_biome == biome) {
                palette_index = @intCast(i);
                found = true;
                break;
            }
        }

        if (!found) {
            palette_index = @intCast(self.palette.items.len);
            try self.palette.append(self.allocator, biome);
        }

        const index = self.getIndex(bx, by, bz);
        self.biomes.items[index] = palette_index;
    }

    fn getIndex(self: *const BiomeStorage, bx: u8, by: u8, bz: u8) usize {
        const dx = (@as(usize, bx) & (self.size[0] - 1)) << 8;
        const dy = @as(usize, by) & (self.size[1] - 1);
        const dz = (@as(usize, bz) & (self.size[2] - 1)) << 4;
        return dx | dy | dz;
    }

    pub fn serialize(self: *const BiomeStorage, stream: *BinaryStream) !void {
        var bits_per_biome = if (self.palette.items.len > 1)
            @as(u8, @intCast(std.math.log2_int_ceil(usize, self.palette.items.len)))
        else
            0;

        bits_per_biome = switch (bits_per_biome) {
            0, 1, 2, 3, 4, 5, 6 => bits_per_biome,
            7, 8 => 8,
            else => 16,
        };

        try stream.writeUint8(bits_per_biome << 1);

        if (bits_per_biome == 0) {
            try stream.writeInt32(@intCast(self.palette.items[0]), .Little);
        } else {
            const biomes_per_word: usize = 32 / bits_per_biome;
            const word_count: usize = (MAX_SIZE + biomes_per_word - 1) / biomes_per_word;

            var w: usize = 0;
            while (w < word_count) : (w += 1) {
                var word: u32 = 0;
                var biome: usize = 0;
                while (biome < biomes_per_word) : (biome += 1) {
                    const index = w * biomes_per_word + biome;
                    if (index >= 4096) break;

                    const state = self.biomes.items[index];
                    const offset: u5 = @intCast(biome * bits_per_biome);
                    word |= state << offset;
                }
                try stream.writeInt32(@bitCast(word), .Little);
            }

            try stream.writeZigZag(@intCast(self.palette.items.len));
            for (self.palette.items) |biome_id| {
                try stream.writeZigZag(@intCast(biome_id));
            }
        }
    }

    pub fn deserialize(stream: *BinaryStream, allocator: std.mem.Allocator) !BiomeStorage {
        const palette_and_flag = try stream.readUint8();
        const bits_per_biome = palette_and_flag >> 1;

        if (bits_per_biome == 0x7f) {
            return try BiomeStorage.init(allocator);
        }

        if (bits_per_biome == 0) {
            const biome_id: u32 = @intCast(try stream.readInt32(.Little));
            var palette = std.ArrayList(u32){
                .items = &[_]u32{},
                .capacity = 0,
            };
            try palette.append(allocator, biome_id);

            var biomes = std.ArrayList(u32){
                .items = &[_]u32{},
                .capacity = 0,
            };
            try biomes.appendNTimes(allocator, 0, MAX_SIZE);

            return BiomeStorage{
                .allocator = allocator,
                .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
                .palette = palette,
                .biomes = biomes,
            };
        }

        const biomes_per_word: usize = 32 / bits_per_biome;
        const word_count: usize = (MAX_SIZE + biomes_per_word - 1) / biomes_per_word;

        var words = try allocator.alloc(u32, word_count);
        defer allocator.free(words);

        for (0..word_count) |i| {
            const word_signed = try stream.readInt32(.Little);
            words[i] = @bitCast(word_signed);
        }
        const palette_size: usize = @intCast(try stream.readZigZag());
        var palette = std.ArrayList(u32){
            .items = &[_]u32{},
            .capacity = 0,
        };
        for (0..palette_size) |_| {
            const biome_id: u32 = @intCast(try stream.readZigZag());
            try palette.append(allocator, biome_id);
        }

        var biomes = std.ArrayList(u32){
            .items = &[_]u32{},
            .capacity = 0,
        };
        try biomes.appendNTimes(allocator, 0, 4096);

        var storage = BiomeStorage{
            .allocator = allocator,
            .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
            .palette = palette,
            .biomes = biomes,
        };

        var position: usize = 0;
        for (words) |word| {
            var biome: usize = 0;
            while (biome < biomes_per_word and position < 4096) : ({
                biome += 1;
                position += 1;
            }) {
                const mask: u32 = (@as(u32, 1) << @intCast(bits_per_biome)) - 1;
                const shift: u5 = @intCast(biome * bits_per_biome);
                const state = (word >> shift) & mask;

                const x: u8 = @intCast((position >> 8) & 0xf);
                const y: u8 = @intCast(position & 0xf);
                const z: u8 = @intCast((position >> 4) & 0xf);

                storage.biomes.items[storage.getIndex(x, y, z)] = state;
            }
        }

        return storage;
    }
};
