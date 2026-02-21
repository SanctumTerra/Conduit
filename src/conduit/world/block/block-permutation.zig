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

    const HASH_OFFSET: i32 = @bitCast(@as(u32, 0x811c9dc5));

    pub fn initRegistry(allocator: std.mem.Allocator) !void {
        if (!permutations_initialized) {
            permutations = std.AutoHashMap(i32, *BlockPermutation).init(allocator);
            permutations_initialized = true;
        }
    }

    pub fn deinitRegistry() void {
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

    /// TODO: Implement when needed for world saving
    pub fn toNBT(self: *const BlockPermutation, allocator: std.mem.Allocator) !NBT.Tag {
        _ = self;
        _ = allocator;
        return error.NotImplemented;
    }

    /// TODO: Implement when needed for world loading
    pub fn fromNBT(allocator: std.mem.Allocator, nbt: NBT.Tag) !*BlockPermutation {
        _ = allocator;
        _ = nbt;
        return error.NotImplemented;
    }

    pub fn calculateHash(allocator: std.mem.Allocator, identifier: []const u8, state: BlockState) !i32 {
        _ = allocator;
        var hash: i32 = HASH_OFFSET;

        for (identifier) |byte| {
            hash ^= @as(i32, byte);
            hash = @bitCast(@as(u32, @bitCast(hash)) *% 16777619);
        }

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
            for (key) |byte| {
                hash ^= @as(i32, byte);
                hash = @bitCast(@as(u32, @bitCast(hash)) *% 16777619);
            }

            const value = state.get(key).?;
            switch (value) {
                .boolean => |b| {
                    hash ^= if (b) @as(i32, 1) else @as(i32, 0);
                    hash = @bitCast(@as(u32, @bitCast(hash)) *% 16777619);
                },
                .integer => |i| {
                    const bytes = std.mem.asBytes(&i);
                    for (bytes) |byte| {
                        hash ^= @as(i32, byte);
                        hash = @bitCast(@as(u32, @bitCast(hash)) *% 16777619);
                    }
                },
                .string => |s| {
                    for (s) |byte| {
                        hash ^= @as(i32, byte);
                        hash = @bitCast(@as(u32, @bitCast(hash)) *% 16777619);
                    }
                },
            }
        }

        return hash;
    }
};
