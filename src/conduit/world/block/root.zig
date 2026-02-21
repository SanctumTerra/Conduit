const std = @import("std");
const Data = @import("protocol").Data;

pub const BlockStateValue = @import("./block-permutation.zig").BlockStateValue;
pub const BlockState = @import("./block-permutation.zig").BlockState;
pub const BlockPermutation = @import("./block-permutation.zig").BlockPermutation;
pub const BlockType = @import("./block-type.zig").BlockType;

pub fn loadBlockPermutations(allocator: std.mem.Allocator) !usize {
    var loader = Data.BlockPermutationLoader.init(allocator);
    defer loader.deinit();
    _ = try loader.load();

    var loaded: usize = 0;
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
        errdefer {
            var iter = state.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                if (entry.value_ptr.* == .string) {
                    allocator.free(entry.value_ptr.string);
                }
            }
            state.deinit();
        }

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

        loaded += 1;
    }

    return loaded;
}

pub fn initRegistries(allocator: std.mem.Allocator) !void {
    try BlockPermutation.initRegistry(allocator);
    try BlockType.initRegistry(allocator);
}

pub fn deinitRegistries() void {
    BlockType.deinitRegistry();
    BlockPermutation.deinitRegistry();
}
