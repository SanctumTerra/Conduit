const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const BlockPermutation = @import("../../block/block-permutation.zig").BlockPermutation;

pub const BlockStorage = struct {
    const MAX_X = 16;
    const MAX_Y = 16;
    const MAX_Z = 16;
    const MAX_SIZE = 16 * 16 * 16;

    allocator: std.mem.Allocator,
    size: [3]usize,
    palette: std.ArrayList(i32),
    blocks: std.ArrayList(u32),
    air: i32,

    pub fn init(allocator: std.mem.Allocator) !BlockStorage {
        const air_perm = try BlockPermutation.resolve(allocator, "minecraft:air", null);
        const air_id = air_perm.network_id;

        var palette = std.ArrayList(i32){
            .items = &[_]i32{},
            .capacity = 0,
        };
        try palette.append(allocator, air_id);

        var blocks = std.ArrayList(u32){
            .items = &[_]u32{},
            .capacity = 0,
        };
        try blocks.appendNTimes(allocator, 0, MAX_SIZE);

        return BlockStorage{
            .allocator = allocator,
            .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
            .palette = palette,
            .blocks = blocks,
            .air = air_id,
        };
    }

    pub fn deinit(self: *BlockStorage) void {
        self.palette.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
    }

    pub fn isEmpty(self: *const BlockStorage) bool {
        return self.palette.items.len == 1 and self.palette.items[0] == self.air;
    }

    pub fn getState(self: *const BlockStorage, bx: u8, by: u8, bz: u8) i32 {
        const index = self.getIndex(bx, by, bz);
        const palette_index = self.blocks.items[index];
        return self.palette.items[palette_index];
    }

    pub fn setState(self: *BlockStorage, bx: u8, by: u8, bz: u8, state: i32) !void {
        var palette_index: u32 = 0;
        var found = false;
        for (self.palette.items, 0..) |pal_state, i| {
            if (pal_state == state) {
                palette_index = @intCast(i);
                found = true;
                break;
            }
        }

        if (!found) {
            palette_index = @intCast(self.palette.items.len);
            try self.palette.append(self.allocator, state);
        }

        const index = self.getIndex(bx, by, bz);
        self.blocks.items[index] = palette_index;
    }

    fn getIndex(self: *const BlockStorage, bx: u8, by: u8, bz: u8) usize {
        const dx = (@as(usize, bx) & (self.size[0] - 1)) << 8;
        const dy = @as(usize, by) & (self.size[1] - 1);
        const dz = (@as(usize, bz) & (self.size[2] - 1)) << 4;
        return dx | dy | dz;
    }

    fn encodeZigZag32(value: i32) u32 {
        const shifted: i32 = value << 1;
        const sign: i32 = value >> 31;
        const result: i32 = shifted ^ sign;
        return @bitCast(result);
    }

    fn decodeZigZag32(value: u32) i32 {
        const shifted: u32 = value >> 1;
        const sign: u32 = @intCast(-(value & 1));
        return @bitCast(shifted ^ sign);
    }

    pub fn serialize(self: *const BlockStorage, stream: *BinaryStream) !void {
        var bits_per_block = if (self.palette.items.len > 1)
            @as(u8, @intCast(std.math.log2_int_ceil(usize, self.palette.items.len)))
        else
            1;

        bits_per_block = switch (bits_per_block) {
            0 => 1,
            1, 2, 3, 4, 5, 6 => bits_per_block,
            7, 8 => 8,
            else => 16,
        };

        try stream.writeUint8((bits_per_block << 1) | 1);

        const blocks_per_word: usize = 32 / bits_per_block;
        const word_count: usize = (4096 + blocks_per_word - 1) / blocks_per_word;

        var w: usize = 0;
        while (w < word_count) : (w += 1) {
            var word: u32 = 0;
            var block: usize = 0;
            while (block < blocks_per_word) : (block += 1) {
                const index = w * blocks_per_word + block;
                if (index >= 4096) break;

                const state = self.blocks.items[index];
                const offset: u5 = @intCast(block * bits_per_block);
                word |= state << offset;
            }
            try stream.writeInt32(@bitCast(word), .Little);
        }

        const palette_len_encoded = encodeZigZag32(@intCast(self.palette.items.len));
        try stream.writeVarInt(palette_len_encoded);

        for (self.palette.items) |state| {
            const encoded = encodeZigZag32(state);
            try stream.writeVarInt(encoded);
        }
    }

    pub fn deserialize(stream: *BinaryStream, allocator: std.mem.Allocator) !BlockStorage {
        const palette_and_flag = try stream.readUint8();
        const bits_per_block = palette_and_flag >> 1;

        const blocks_per_word: usize = 32 / bits_per_block;
        const word_count: usize = (4096 + blocks_per_word - 1) / blocks_per_word;

        var words = try allocator.alloc(u32, word_count);
        defer allocator.free(words);

        for (0..word_count) |i| {
            const word_signed = try stream.readInt32(.Little);
            words[i] = @bitCast(word_signed);
        }

        const palette_size_encoded = try stream.readVarInt();
        const palette_size: usize = @intCast(decodeZigZag32(palette_size_encoded));

        var palette = std.ArrayList(i32){
            .items = &[_]i32{},
            .capacity = 0,
        };
        for (0..palette_size) |_| {
            const encoded = try stream.readVarInt();
            const state = decodeZigZag32(encoded);
            try palette.append(allocator, state);
        }

        var blocks = std.ArrayList(u32){
            .items = &[_]u32{},
            .capacity = 0,
        };
        try blocks.appendNTimes(allocator, 0, 4096);

        var position: usize = 0;
        const air_perm = try BlockPermutation.resolve(allocator, "minecraft:air", null);
        const air_id = air_perm.network_id;

        var storage = BlockStorage{
            .allocator = allocator,
            .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
            .palette = palette,
            .blocks = blocks,
            .air = air_id,
        };

        for (words) |word| {
            var block: usize = 0;
            while (block < blocks_per_word and position < 4096) : ({
                block += 1;
                position += 1;
            }) {
                const mask: u32 = (@as(u32, 1) << @intCast(bits_per_block)) - 1;
                const shift: u5 = @intCast(block * bits_per_block);
                const state = (word >> shift) & mask;

                const x: u8 = @intCast((position >> 8) & 0xf);
                const y: u8 = @intCast(position & 0xf);
                const z: u8 = @intCast((position >> 4) & 0xf);

                storage.blocks.items[storage.getIndex(x, y, z)] = state;
            }
        }

        return storage;
    }
};
