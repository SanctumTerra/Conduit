const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const BlockPermutation = @import("../../block/block-permutation.zig").BlockPermutation;
const BlockState = @import("../../block/block-permutation.zig").BlockState;
const NBT = @import("nbt");

fn computePermutationHashFast(identifier: []const u8, state_tag: ?NBT.CompoundTag) i32 {
    const FNV_OFFSET: u32 = 0x811c9dc5;
    const FNV_PRIME: u32 = 16777619;

    var buf: [8192]u8 = undefined;
    var pos: usize = 0;

    buf[pos] = 10;
    pos += 1;
    buf[pos] = 0;
    pos += 1;
    buf[pos] = 0;
    pos += 1;

    buf[pos] = 8;
    pos += 1;
    const name_key = "name";
    const name_len: u16 = @intCast(name_key.len);
    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, name_len))));
    pos += 2;
    @memcpy(buf[pos .. pos + name_key.len], name_key);
    pos += name_key.len;
    const id_len: u16 = @intCast(identifier.len);
    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, id_len))));
    pos += 2;
    @memcpy(buf[pos .. pos + identifier.len], identifier);
    pos += identifier.len;

    buf[pos] = 10;
    pos += 1;
    const states_key = "states";
    const states_len: u16 = @intCast(states_key.len);
    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, states_len))));
    pos += 2;
    @memcpy(buf[pos .. pos + states_key.len], states_key);
    pos += states_key.len;

    if (state_tag) |st| {
        var keys_buf: [64][]const u8 = undefined;
        var keys_count: usize = 0;
        var it = st.value.iterator();
        while (it.next()) |entry| {
            if (keys_count < keys_buf.len) {
                keys_buf[keys_count] = entry.key_ptr.*;
                keys_count += 1;
            }
        }
        const keys = keys_buf[0..keys_count];
        std.mem.sort([]const u8, keys, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        for (keys) |key| {
            const val = st.value.get(key) orelse continue;
            const klen: u16 = @intCast(key.len);
            switch (val) {
                .Byte => |b| {
                    buf[pos] = 1;
                    pos += 1;
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, klen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + key.len], key);
                    pos += key.len;
                    buf[pos] = @bitCast(b.value);
                    pos += 1;
                },
                .Int => |iv| {
                    buf[pos] = 3;
                    pos += 1;
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, klen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + key.len], key);
                    pos += key.len;
                    @memcpy(buf[pos .. pos + 4], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, iv.value))));
                    pos += 4;
                },
                .String => |sv| {
                    buf[pos] = 8;
                    pos += 1;
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, klen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + key.len], key);
                    pos += key.len;
                    const slen: u16 = @intCast(sv.value.len);
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, slen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + sv.value.len], sv.value);
                    pos += sv.value.len;
                },
                else => {},
            }
        }
    }

    buf[pos] = 0;
    pos += 1;
    buf[pos] = 0;
    pos += 1;

    var hash: u32 = FNV_OFFSET;
    for (buf[0..pos]) |byte| {
        hash ^= byte;
        hash *%= FNV_PRIME;
    }
    return @bitCast(hash);
}

pub const BlockStorage = struct {
    const MAX_X = 16;
    const MAX_Y = 16;
    const MAX_Z = 16;
    const MAX_SIZE = 16 * 16 * 16;

    allocator: std.mem.Allocator,
    size: [3]usize,
    palette_buf: [256]i32,
    palette_len: usize,
    blocks: *[4096]u32,
    air: i32,

    pub fn paletteSlice(self: *const BlockStorage) []const i32 {
        return self.palette_buf[0..self.palette_len];
    }

    pub fn init(allocator: std.mem.Allocator) !BlockStorage {
        const air_perm = try BlockPermutation.resolve(allocator, "minecraft:air", null);
        const air_id = air_perm.network_id;

        var palette_buf: [256]i32 = undefined;
        palette_buf[0] = air_id;

        const blocks = try allocator.create([4096]u32);
        @memset(blocks, 0);

        return BlockStorage{
            .allocator = allocator,
            .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
            .palette_buf = palette_buf,
            .palette_len = 1,
            .blocks = blocks,
            .air = air_id,
        };
    }

    pub fn deinit(self: *BlockStorage) void {
        self.allocator.destroy(self.blocks);
    }

    pub fn isEmpty(self: *const BlockStorage) bool {
        return self.palette_len == 1 and self.palette_buf[0] == self.air;
    }

    pub fn getState(self: *const BlockStorage, bx: u8, by: u8, bz: u8) i32 {
        const index = self.getIndex(bx, by, bz);
        const palette_index = self.blocks[index];
        return self.palette_buf[palette_index];
    }

    pub fn setState(self: *BlockStorage, bx: u8, by: u8, bz: u8, state: i32) !void {
        var palette_index: u32 = 0;
        var found = false;
        for (self.paletteSlice(), 0..) |pal_state, i| {
            if (pal_state == state) {
                palette_index = @intCast(i);
                found = true;
                break;
            }
        }

        if (!found) {
            if (self.palette_len >= 256) return error.PaletteOverflow;
            palette_index = @intCast(self.palette_len);
            self.palette_buf[self.palette_len] = state;
            self.palette_len += 1;
        }

        const index = self.getIndex(bx, by, bz);
        self.blocks[index] = palette_index;
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
        const sign: u32 = 0 -% (value & 1);
        return @bitCast(shifted ^ sign);
    }

    pub fn serialize(self: *const BlockStorage, stream: *BinaryStream) !void {
        var bits_per_block = if (self.palette_len > 1)
            @as(u8, @intCast(std.math.log2_int_ceil(usize, self.palette_len)))
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

                const state = self.blocks[index];
                const offset: u5 = @intCast(block * bits_per_block);
                word |= state << offset;
            }
            try stream.writeInt32(@bitCast(word), .Little);
        }

        const palette_len_encoded = encodeZigZag32(@intCast(self.palette_len));
        try stream.writeVarInt(palette_len_encoded);

        for (self.paletteSlice()) |state| {
            const encoded = encodeZigZag32(state);
            try stream.writeVarInt(encoded);
        }
    }

    pub fn serializePersistence(self: *const BlockStorage, stream: *BinaryStream, allocator: std.mem.Allocator) !void {
        var bits_per_block = if (self.palette_len > 1)
            @as(u8, @intCast(std.math.log2_int_ceil(usize, self.palette_len)))
        else
            1;

        bits_per_block = switch (bits_per_block) {
            0 => 1,
            1, 2, 3, 4, 5, 6 => bits_per_block,
            7, 8 => 8,
            else => 16,
        };

        try stream.writeUint8(bits_per_block << 1);

        const blocks_per_word: usize = 32 / bits_per_block;
        const word_count: usize = (4096 + blocks_per_word - 1) / blocks_per_word;

        var w: usize = 0;
        while (w < word_count) : (w += 1) {
            var word: u32 = 0;
            var block: usize = 0;
            while (block < blocks_per_word) : (block += 1) {
                const index = w * blocks_per_word + block;
                if (index >= 4096) break;
                const state = self.blocks[index];
                const offset: u5 = @intCast(block * bits_per_block);
                word |= state << offset;
            }
            try stream.writeInt32(@bitCast(word), .Little);
        }

        try stream.writeInt32(@intCast(self.palette_len), .Little);

        const nbt_opts = NBT.ReadWriteOptions{ .name = true, .tag_type = true, .varint = false, .endian = .Little };
        for (self.paletteSlice()) |state| {
            const perm = BlockPermutation.getByNetworkId(state) orelse continue;
            var compound = perm.toNBT(allocator) catch continue;
            defer compound.deinit(allocator);
            try NBT.CompoundTag.write(stream, &compound, nbt_opts);
        }
    }

    pub fn deserialize(stream: *BinaryStream, allocator: std.mem.Allocator) !BlockStorage {
        const palette_and_flag = try stream.readUint8();
        const bits_per_block: u8 = palette_and_flag >> 1;
        const is_runtime = (palette_and_flag & 1) != 0;

        if (bits_per_block > 16) return error.InvalidBitsPerBlock;

        var words: ?[]u32 = null;
        defer if (words) |w| allocator.free(w);

        if (bits_per_block > 0) {
            const blocks_per_word: usize = 32 / bits_per_block;
            const word_count: usize = (4096 + blocks_per_word - 1) / blocks_per_word;
            words = try allocator.alloc(u32, word_count);
            for (0..word_count) |i| {
                words.?[i] = @bitCast(try stream.readInt32(.Little));
            }
        }

        var palette_buf: [256]i32 = undefined;
        var palette_len: usize = 0;

        if (is_runtime) {
            const palette_size_encoded = try stream.readVarInt();
            const palette_size: usize = @intCast(decodeZigZag32(palette_size_encoded));
            for (0..palette_size) |_| {
                const encoded = try stream.readVarInt();
                const state = decodeZigZag32(encoded);
                if (palette_len >= 256) return error.PaletteOverflow;
                palette_buf[palette_len] = state;
                palette_len += 1;
            }
        } else {
            const palette_size: usize = @intCast(try stream.readInt32(.Little));
            for (0..palette_size) |_| {
                const nbt_opts = NBT.ReadWriteOptions{ .name = true, .tag_type = true, .varint = false, .endian = .Little };
                var compound = NBT.CompoundTag.read(stream, allocator, nbt_opts) catch {
                    if (palette_len >= 256) return error.PaletteOverflow;
                    palette_buf[palette_len] = 0;
                    palette_len += 1;
                    continue;
                };
                defer compound.deinit(allocator);

                const name_tag = compound.get("name") orelse {
                    if (palette_len >= 256) return error.PaletteOverflow;
                    palette_buf[palette_len] = 0;
                    palette_len += 1;
                    continue;
                };
                const identifier = if (name_tag == .String) name_tag.String.value else {
                    if (palette_len >= 256) return error.PaletteOverflow;
                    palette_buf[palette_len] = 0;
                    palette_len += 1;
                    continue;
                };

                var state_tag: ?NBT.CompoundTag = null;
                if (compound.get("states")) |st| {
                    if (st == .Compound) state_tag = st.Compound;
                }

                const network_id = computePermutationHashFast(identifier, state_tag);
                if (palette_len >= 256) return error.PaletteOverflow;
                if (BlockPermutation.lookupByNbtHash(network_id)) |looked_up_id| {
                    palette_buf[palette_len] = looked_up_id;
                    palette_len += 1;
                } else if (BlockPermutation.getByNetworkId(network_id)) |_| {
                    palette_buf[palette_len] = network_id;
                    palette_len += 1;
                } else {
                    const perm = BlockPermutation.resolve(allocator, identifier, null) catch {
                        palette_buf[palette_len] = 0;
                        palette_len += 1;
                        continue;
                    };
                    palette_buf[palette_len] = perm.network_id;
                    palette_len += 1;
                }
            }
        }

        const blocks = try allocator.create([4096]u32);
        @memset(blocks, 0);

        const air_perm = try BlockPermutation.resolve(allocator, "minecraft:air", null);
        const air_id = air_perm.network_id;

        var storage = BlockStorage{
            .allocator = allocator,
            .size = [3]usize{ MAX_X, MAX_Y, MAX_Z },
            .palette_buf = palette_buf,
            .palette_len = palette_len,
            .blocks = blocks,
            .air = air_id,
        };

        if (words) |w| {
            const blocks_per_word: usize = 32 / bits_per_block;
            var position: usize = 0;
            for (w) |word| {
                var block: usize = 0;
                while (block < blocks_per_word and position < 4096) : ({
                    block += 1;
                    position += 1;
                }) {
                    const mask: u32 = (@as(u32, 1) << @intCast(bits_per_block)) - 1;
                    const shift: u5 = @intCast(block * bits_per_block);
                    const state = (word >> shift) & mask;
                    storage.blocks[position] = state;
                }
            }
        }

        return storage;
    }
};

test "computePermutationHashFast matches calculateHash" {
    const allocator = std.testing.allocator;

    const identifiers = [_][]const u8{
        "minecraft:stone",
        "minecraft:air",
        "minecraft:oak_planks",
        "minecraft:grass_block",
        "minecraft:cobblestone",
    };

    for (identifiers) |identifier| {
        const hash_fast = computePermutationHashFast(identifier, null);

        var empty_state = BlockState.init(allocator);
        defer empty_state.deinit();
        const hash_calc = try BlockPermutation.calculateHash(allocator, identifier, empty_state);

        try std.testing.expectEqual(hash_calc, hash_fast);
    }

    {
        var state_nbt = NBT.CompoundTag.init(allocator, null);
        defer state_nbt.deinit(allocator);
        try state_nbt.set("facing", .{ .String = NBT.StringTag.init(try allocator.dupe(u8, "north"), null) });
        try state_nbt.set("open", .{ .Byte = NBT.ByteTag.init(1, null) });

        const hash_fast = computePermutationHashFast("minecraft:oak_door", state_nbt);

        var state_bs = BlockState.init(allocator);
        defer {
            var it = state_bs.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                if (entry.value_ptr.* == .string) allocator.free(entry.value_ptr.string);
            }
            state_bs.deinit();
        }
        try state_bs.put(try allocator.dupe(u8, "facing"), .{ .string = try allocator.dupe(u8, "north") });
        try state_bs.put(try allocator.dupe(u8, "open"), .{ .boolean = true });

        const hash_calc = try BlockPermutation.calculateHash(allocator, "minecraft:oak_door", state_bs);

        try std.testing.expectEqual(hash_calc, hash_fast);
    }

    {
        var state_nbt = NBT.CompoundTag.init(allocator, null);
        defer state_nbt.deinit(allocator);
        try state_nbt.set("age", .{ .Int = NBT.IntTag.init(7, null) });

        const hash_fast = computePermutationHashFast("minecraft:wheat", state_nbt);

        var state_bs = BlockState.init(allocator);
        defer {
            var it = state_bs.iterator();
            while (it.next()) |entry| allocator.free(entry.key_ptr.*);
            state_bs.deinit();
        }
        try state_bs.put(try allocator.dupe(u8, "age"), .{ .integer = 7 });

        const hash_calc = try BlockPermutation.calculateHash(allocator, "minecraft:wheat", state_bs);

        try std.testing.expectEqual(hash_calc, hash_fast);
    }
}
