const std = @import("std");
const Data = @import("../root.zig");

pub const BlockPermutationData = struct {
    identifier: []const u8,
    hash: i32,
    state: std.json.Value,
};

pub const BlockPermutationLoader = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    permutations: std.ArrayList(BlockPermutationData),

    pub fn init(allocator: std.mem.Allocator) BlockPermutationLoader {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .permutations = .{},
        };
    }

    pub fn deinit(self: *BlockPermutationLoader) void {
        self.permutations.deinit(self.allocator);
        self.arena.deinit();
    }

    pub fn load(self: *BlockPermutationLoader) !usize {
        const json_data = Data.block_permutations_json;
        const arena_allocator = self.arena.allocator();

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            arena_allocator,
            json_data,
            .{},
        );

        const root = parsed.value;
        if (root != .array) return error.InvalidJsonFormat;

        const array = root.array;
        try self.permutations.ensureTotalCapacity(self.allocator, array.items.len);

        for (array.items) |item| {
            if (item != .object) continue;
            const obj = item.object;

            const identifier = if (obj.get("identifier")) |id|
                if (id == .string) id.string else continue
            else
                continue;

            const hash = if (obj.get("hash")) |h|
                if (h == .integer) @as(i32, @intCast(h.integer)) else continue
            else
                continue;

            const state = obj.get("state") orelse continue;

            try self.permutations.append(self.allocator, .{
                .identifier = identifier,
                .hash = hash,
                .state = state,
            });
        }

        return self.permutations.items.len;
    }

    pub fn getPermutations(self: *const BlockPermutationLoader) []const BlockPermutationData {
        return self.permutations.items;
    }

    pub fn count(self: *const BlockPermutationLoader) usize {
        return self.permutations.items.len;
    }
};
