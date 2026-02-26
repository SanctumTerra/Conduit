const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Block = @import("../block.zig").Block;
const BlockPermutation = @import("../block-permutation.zig").BlockPermutation;
const Player = @import("../../../player/player.zig").Player;
const trait_mod = @import("./trait.zig");

pub const State = struct {};

fn onBreak(_: *State, block: *Block, _: ?*Player) bool {
    const perm = block.getPermutation(0) catch return true;
    const val = perm.state.get("upper_block_bit") orelse return true;
    if (val != .boolean) return true;

    const other_pos = if (val.boolean)
        Protocol.BlockPosition{ .x = block.position.x, .y = block.position.y - 1, .z = block.position.z }
    else
        Protocol.BlockPosition{ .x = block.position.x, .y = block.position.y + 1, .z = block.position.z };

    const air = BlockPermutation.resolve(block.allocator, "minecraft:air", null) catch return true;
    block.dimension.setPermutation(other_pos, air, 0) catch {};

    const conduit = block.dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();
    const network_id: u32 = @bitCast(air.network_id);
    for (snapshots) |p| {
        if (!p.spawned) continue;
        var s = BinaryStream.init(block.allocator, null, null);
        defer s.deinit();
        const update = Protocol.UpdateBlockPacket{
            .position = other_pos,
            .networkBlockId = network_id,
        };
        const serialized = update.serialize(&s) catch continue;
        p.network.sendPacket(p.connection, serialized) catch {};
    }

    return true;
}

pub const UpperBlockTrait = trait_mod.BlockTrait(State, .{
    .identifier = "upper_block",
    .onBreak = &onBreak,
});
