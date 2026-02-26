const std = @import("std");
const Protocol = @import("protocol");
const BlockPermutation = @import("../block-permutation.zig").BlockPermutation;
const BlockState = @import("../block-permutation.zig").BlockState;
const BlockStateValue = @import("../block-permutation.zig").BlockStateValue;
const BlockType = @import("../block-type.zig").BlockType;

pub const PlacementContext = struct {
    yaw: f32,
    pitch: f32,
    block_face: i32,
    clicked_position: ?Protocol.Vector3f,
};

pub fn resolveWithPlacement(allocator: std.mem.Allocator, permutation: *BlockPermutation, ctx: PlacementContext) *BlockPermutation {
    const block_type = BlockType.get(permutation.identifier) orelse return permutation;

    var state = BlockState.init(allocator);
    defer state.deinit();

    var iter = permutation.state.iterator();
    while (iter.next()) |entry| {
        state.put(entry.key_ptr.*, entry.value_ptr.*) catch return permutation;
    }

    var changed = false;

    if (permutation.state.contains("minecraft:cardinal_direction")) {
        state.put("minecraft:cardinal_direction", .{ .string = oppositeCardinal(ctx.yaw) }) catch return permutation;
        changed = true;
    }

    if (permutation.state.contains("direction")) {
        state.put("direction", .{ .integer = oppositeCardinalInt(ctx.yaw) }) catch return permutation;
        changed = true;
    }

    if (permutation.state.contains("facing_direction")) {
        const pitch = @ceil(ctx.pitch);
        const val: i32 = if (pitch >= 80) 1 else if (pitch <= -80) 0 else oppositeCardinalFacing(ctx.yaw);
        state.put("facing_direction", .{ .integer = val }) catch return permutation;
        changed = true;
    }

    if (permutation.state.contains("pillar_axis")) {
        const axis: []const u8 = switch (ctx.block_face) {
            4, 5 => "x",
            0, 1 => "y",
            2, 3 => "z",
            else => "y",
        };
        state.put("pillar_axis", .{ .string = axis }) catch return permutation;
        changed = true;
    }

    if (permutation.state.contains("weirdo_direction")) {
        state.put("weirdo_direction", .{ .integer = cardinalInt(ctx.yaw) }) catch return permutation;
        changed = true;
    }

    if (permutation.state.contains("minecraft:vertical_half")) {
        if (ctx.clicked_position) |click| {
            const half: []const u8 = if (click.y > 0.5 and click.y < 0.99) "top" else "bottom";
            state.put("minecraft:vertical_half", .{ .string = half }) catch return permutation;
            changed = true;
        }
    }

    if (!changed) return permutation;
    return block_type.getPermutation(state);
}

fn oppositeCardinal(yaw: f32) []const u8 {
    const rotation = @mod(@floor(yaw) + 360.0, 360.0);
    if (rotation >= 315 or rotation < 45) return "north";
    if (rotation >= 45 and rotation < 135) return "east";
    if (rotation >= 135 and rotation < 225) return "south";
    return "west";
}

fn oppositeCardinalInt(yaw: f32) i32 {
    const rotation = @mod(@floor(yaw) + 360.0, 360.0);
    if (rotation >= 315 or rotation < 45) return 2;
    if (rotation >= 45 and rotation < 135) return 3;
    if (rotation >= 135 and rotation < 225) return 0;
    return 1;
}

fn oppositeCardinalFacing(yaw: f32) i32 {
    const rotation = @mod(@floor(yaw) + 360.0, 360.0);
    if (rotation >= 315 or rotation < 45) return 2;
    if (rotation >= 45 and rotation < 135) return 5;
    if (rotation >= 135 and rotation < 225) return 3;
    return 4;
}

fn cardinalInt(yaw: f32) i32 {
    const rotation = @mod(@floor(yaw) + 360.0, 360.0);
    if (rotation >= 315 or rotation < 45) return 2;
    if (rotation >= 45 and rotation < 135) return 1;
    if (rotation >= 135 and rotation < 225) return 3;
    return 0;
}

const Dimension = @import("../../dimension/dimension.zig").Dimension;

pub fn placeUpperBlock(allocator: std.mem.Allocator, dimension: *Dimension, pos: Protocol.BlockPosition, permutation: *BlockPermutation) !void {
    if (!permutation.state.contains("upper_block_bit")) return;
    const val = permutation.state.get("upper_block_bit") orelse return;
    if (val != .boolean or val.boolean) return;

    const block_type = BlockType.get(permutation.identifier) orelse return;
    var state = BlockState.init(allocator);
    defer state.deinit();

    var iter = permutation.state.iterator();
    while (iter.next()) |entry| {
        try state.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    try state.put("upper_block_bit", .{ .boolean = true });

    const upper_perm = block_type.getPermutation(state);
    const above = Protocol.BlockPosition{ .x = pos.x, .y = pos.y + 1, .z = pos.z };
    try dimension.setPermutation(above, upper_perm, 0);

    const BinaryStream = @import("BinaryStream").BinaryStream;
    const conduit = dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();
    const network_id: u32 = @bitCast(upper_perm.network_id);
    for (snapshots) |p| {
        if (!p.spawned) continue;
        var s = BinaryStream.init(allocator, null, null);
        defer s.deinit();
        const update = Protocol.UpdateBlockPacket{
            .position = above,
            .networkBlockId = network_id,
        };
        const serialized = update.serialize(&s) catch continue;
        p.network.sendPacket(p.connection, serialized) catch {};
    }

    const trait_apply = @import("./trait.zig").applyTraitsForBlock;
    try trait_apply(allocator, dimension, above);
}
