const std = @import("std");
const NBT = @import("nbt");
const BlockType = @import("./block-type.zig").BlockType;

pub const BlockStateValue = union(enum) {
    boolean: bool,
    integer: i32,
    string: []const u8,

    pub fn eql(self: BlockStateValue, other: BlockStateValue) bool {
        return switch (self) {
            .boolean => |b| if (other == .boolean) b == other.boolean else false,
            .integer => |i| if (other == .integer) i == other.integer else false,
            .string => |s| if (other == .string) std.mem.eql(u8, s, other.string) else false,
        };
    }
};

pub const BlockState = std.StringHashMap(BlockStateValue);

pub const BlockPermutation = struct {
    network_id: i32,
    identifier: []const u8,
    state: BlockState,
    allocator: std.mem.Allocator,

    var permutations: std.AutoHashMap(i32, *BlockPermutation) = undefined;
    var permutations_initialized = false;
    var nbt_hash_to_network_id: std.AutoHashMap(i32, i32) = undefined;
    var nbt_hash_lookup_initialized = false;

    const HASH_OFFSET: i32 = @bitCast(@as(u32, 0x811c9dc5));

    pub fn initRegistry(allocator: std.mem.Allocator) !void {
        if (!permutations_initialized) {
            permutations = std.AutoHashMap(i32, *BlockPermutation).init(allocator);
            permutations_initialized = true;
        }
    }

    pub fn deinitRegistry() void {
        if (nbt_hash_lookup_initialized) {
            nbt_hash_to_network_id.deinit();
            nbt_hash_lookup_initialized = false;
        }
        if (permutations_initialized) {
            var iter = permutations.valueIterator();
            while (iter.next()) |perm| {
                perm.*.deinit();
            }
            permutations.deinit();
            permutations_initialized = false;
        }
    }

    pub fn init(allocator: std.mem.Allocator, network_id: i32, identifier: []const u8, state: BlockState) !*BlockPermutation {
        const perm = try allocator.create(BlockPermutation);
        perm.* = BlockPermutation{
            .network_id = network_id,
            .identifier = try allocator.dupe(u8, identifier),
            .state = state,
            .allocator = allocator,
        };
        return perm;
    }

    pub fn deinit(self: *BlockPermutation) void {
        self.allocator.free(self.identifier);
        var iter = self.state.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.* == .string) {
                self.allocator.free(entry.value_ptr.string);
            }
        }
        self.state.deinit();
        self.allocator.destroy(self);
    }

    pub fn resolve(_: std.mem.Allocator, identifier: []const u8, state: ?BlockState) !*BlockPermutation {
        const block_type = BlockType.get(identifier);
        if (block_type == null) {
            const air_type = BlockType.get("minecraft:air");
            if (air_type) |air| {
                if (air.getDefaultPermutation()) |air_perm| {
                    return air_perm;
                }
            }
            return error.BlockTypeNotFound;
        }

        if (state) |s| {
            return block_type.?.getPermutation(s);
        }

        if (block_type.?.getDefaultPermutation()) |perm| {
            return perm;
        }

        return error.NoPermutationsFound;
    }

    pub fn register(self: *BlockPermutation) !void {
        try permutations.put(self.network_id, self);
    }

    pub fn initNbtHashLookup(allocator: std.mem.Allocator) !void {
        if (nbt_hash_lookup_initialized) return;
        nbt_hash_to_network_id = std.AutoHashMap(i32, i32).init(allocator);
        nbt_hash_lookup_initialized = true;

        var iter = permutations.iterator();
        while (iter.next()) |entry| {
            const perm = entry.value_ptr.*;
            const hash = try calculateHash(allocator, perm.identifier, perm.state);
            try nbt_hash_to_network_id.put(hash, perm.network_id);
        }
    }

    pub fn lookupByNbtHash(hash: i32) ?i32 {
        if (!nbt_hash_lookup_initialized) return null;
        return nbt_hash_to_network_id.get(hash);
    }

    pub fn getByNetworkId(network_id: i32) ?*BlockPermutation {
        return permutations.get(network_id);
    }

    pub fn matches(self: *const BlockPermutation, state: BlockState) bool {
        var iter = state.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            if (self.state.get(key)) |self_value| {
                if (!value.eql(self_value)) {
                    return false;
                }
            } else {
                return false;
            }
        }
        return true;
    }

    pub fn toNBT(self: *const BlockPermutation, allocator: std.mem.Allocator) !NBT.CompoundTag {
        var root = NBT.CompoundTag.init(allocator, null);
        try root.set("name", .{ .String = NBT.StringTag.init(try allocator.dupe(u8, self.identifier), null) });

        var states = NBT.CompoundTag.init(allocator, null);
        var iter = self.state.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            switch (entry.value_ptr.*) {
                .boolean => |b| try states.set(key, .{ .Byte = NBT.ByteTag.init(if (b) 1 else 0, null) }),
                .integer => |i| try states.set(key, .{ .Int = NBT.IntTag.init(i, null) }),
                .string => |s| try states.set(key, .{ .String = NBT.StringTag.init(try allocator.dupe(u8, s), null) }),
            }
        }
        try root.set("states", .{ .Compound = states });

        return root;
    }

    pub fn calculateHash(_: std.mem.Allocator, identifier: []const u8, state: BlockState) !i32 {
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

        var keys_buf: [64][]const u8 = undefined;
        var keys_count: usize = 0;
        var iter = state.iterator();
        while (iter.next()) |entry| {
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
            const value = state.get(key).?;
            const klen: u16 = @intCast(key.len);
            switch (value) {
                .boolean => |b| {
                    buf[pos] = 1;
                    pos += 1;
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, klen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + key.len], key);
                    pos += key.len;
                    buf[pos] = if (b) 1 else 0;
                    pos += 1;
                },
                .integer => |i| {
                    buf[pos] = 3;
                    pos += 1;
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, klen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + key.len], key);
                    pos += key.len;
                    @memcpy(buf[pos .. pos + 4], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, i))));
                    pos += 4;
                },
                .string => |s| {
                    buf[pos] = 8;
                    pos += 1;
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, klen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + key.len], key);
                    pos += key.len;
                    const slen: u16 = @intCast(s.len);
                    @memcpy(buf[pos .. pos + 2], &@as([2]u8, @bitCast(std.mem.nativeToLittle(u16, slen))));
                    pos += 2;
                    @memcpy(buf[pos .. pos + s.len], s);
                    pos += s.len;
                },
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
};

test "hash lookup returns correct network_id for all permutations" {
    const allocator = std.testing.allocator;
    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();

    try BlockType.initRegistry(allocator);
    defer BlockType.deinitRegistry();

    const Data = @import("protocol").Data;
    var loader = Data.BlockPermutationLoader.init(allocator);
    defer loader.deinit();
    _ = try loader.load();

    var types_created = std.StringHashMap(void).init(allocator);
    defer types_created.deinit();

    for (loader.getPermutations()) |perm_data| {
        const identifier = perm_data.identifier;
        if (!types_created.contains(identifier)) {
            if (BlockType.get(identifier) == null) {
                const block_type = try BlockType.init(allocator, identifier);
                try block_type.register();
            }
            try types_created.put(identifier, {});
        }

        var state = BlockState.init(allocator);
        if (perm_data.state == .object) {
            var iter = perm_data.state.object.iterator();
            while (iter.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = switch (entry.value_ptr.*) {
                    .bool => |b| BlockStateValue{ .boolean = b },
                    .integer => |i| BlockStateValue{ .integer = @intCast(i) },
                    .string => |s| BlockStateValue{ .string = try allocator.dupe(u8, s) },
                    else => continue,
                };
                try state.put(key, value);
            }
        }

        const perm = try BlockPermutation.init(allocator, perm_data.hash, identifier, state);
        try perm.register();

        if (BlockType.get(identifier)) |block_type| {
            try block_type.addPermutation(perm);
        }
    }

    try BlockPermutation.initNbtHashLookup(allocator);

    var iter = BlockPermutation.permutations.iterator();
    var checked: usize = 0;
    while (iter.next()) |entry| {
        const perm = entry.value_ptr.*;
        const hash = try BlockPermutation.calculateHash(allocator, perm.identifier, perm.state);
        const looked_up = BlockPermutation.lookupByNbtHash(hash);
        try std.testing.expect(looked_up != null);
        try std.testing.expectEqual(perm.network_id, looked_up.?);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}
