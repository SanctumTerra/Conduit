const std = @import("std");
const BlockPermutation = @import("../block-permutation.zig").BlockPermutation;
const BlockState = @import("../block-permutation.zig").BlockState;
const BlockType = @import("../block-type.zig").BlockType;

pub fn resolveWithRotation(allocator: std.mem.Allocator, permutation: *BlockPermutation, yaw: f32) *BlockPermutation {
    if (!permutation.state.contains("minecraft:cardinal_direction")) return permutation;

    const direction = oppositeCardinal(yaw);
    const block_type = BlockType.get(permutation.identifier) orelse return permutation;

    var state = BlockState.init(allocator);
    defer state.deinit();

    var iter = permutation.state.iterator();
    while (iter.next()) |entry| {
        state.put(entry.key_ptr.*, entry.value_ptr.*) catch return permutation;
    }
    state.put("minecraft:cardinal_direction", .{ .string = direction }) catch return permutation;

    return block_type.getPermutation(state);
}

fn oppositeCardinal(yaw: f32) []const u8 {
    const rotation = @mod(@floor(yaw) + 360.0, 360.0);
    if (rotation >= 315 or rotation < 45) return "north";
    if (rotation >= 45 and rotation < 135) return "east";
    if (rotation >= 135 and rotation < 225) return "south";
    return "west";
}
