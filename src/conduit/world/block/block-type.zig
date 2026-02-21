const std = @import("std");
const BlockPermutation = @import("./block-permutation.zig").BlockPermutation;
const BlockState = @import("./block-permutation.zig").BlockState;

pub const BlockType = struct {
    identifier: []const u8,
    permutations: std.ArrayList(*BlockPermutation),
    states: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    var types: std.StringHashMap(*BlockType) = undefined;
    var types_initialized = false;

    pub fn initRegistry(allocator: std.mem.Allocator) !void {
        if (!types_initialized) {
            types = std.StringHashMap(*BlockType).init(allocator);
            types_initialized = true;
        }
    }

    pub fn deinitRegistry() void {
        if (types_initialized) {
            var iter = types.valueIterator();
            while (iter.next()) |block_type| {
                block_type.*.deinit();
            }
            types.deinit();
            types_initialized = false;
        }
    }

    pub fn init(allocator: std.mem.Allocator, identifier: []const u8) !*BlockType {
        const block_type = try allocator.create(BlockType);
        block_type.* = BlockType{
            .identifier = try allocator.dupe(u8, identifier),
            .permutations = .{},
            .states = .{},
            .allocator = allocator,
        };
        return block_type;
    }

    pub fn deinit(self: *BlockType) void {
        self.allocator.free(self.identifier);
        self.permutations.deinit(self.allocator);

        for (self.states.items) |state| {
            self.allocator.free(state);
        }
        self.states.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    pub fn get(identifier: []const u8) ?*BlockType {
        return types.get(identifier);
    }

    pub fn register(self: *BlockType) !void {
        try types.put(self.identifier, self);
    }

    pub fn addPermutation(self: *BlockType, permutation: *BlockPermutation) !void {
        try self.permutations.append(self.allocator, permutation);
    }

    pub fn getPermutation(self: *BlockType, state: ?BlockState) *BlockPermutation {
        if (state) |s| {
            for (self.permutations.items) |perm| {
                if (perm.matches(s)) {
                    return perm;
                }
            }
        }

        if (self.permutations.items.len > 0) {
            return self.permutations.items[0];
        }

        unreachable;
    }

    pub fn getDefaultPermutation(self: *BlockType) ?*BlockPermutation {
        if (self.permutations.items.len > 0) {
            return self.permutations.items[0];
        }
        return null;
    }
};
