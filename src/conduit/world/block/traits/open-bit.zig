const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Block = @import("../block.zig").Block;
const BlockType = @import("../block-type.zig").BlockType;
const BlockState = @import("../block-permutation.zig").BlockState;
const Player = @import("../../../player/player.zig").Player;
const trait_mod = @import("./trait.zig");

pub const State = struct {};

fn onInteract(_: *State, block: *Block, _: *Player) bool {
    const perm = block.getPermutation(0) catch return true;
    const val = perm.state.get("open_bit") orelse return true;
    if (val != .boolean) return true;

    if (std.mem.eql(u8, perm.identifier, "minecraft:barrel")) return true;

    const open = !val.boolean;

    const block_type = BlockType.get(perm.identifier) orelse return true;
    var state = BlockState.init(block.allocator);
    defer state.deinit();

    var iter = perm.state.iterator();
    while (iter.next()) |entry| {
        state.put(entry.key_ptr.*, entry.value_ptr.*) catch return true;
    }
    state.put("open_bit", .{ .boolean = open }) catch return true;

    const new_perm = block_type.getPermutation(state);
    block.setPermutation(new_perm, 0) catch return true;

    const event = soundEvent(perm.identifier, open);

    const conduit = block.dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();
    const network_id: u32 = @bitCast(new_perm.network_id);
    for (snapshots) |p| {
        if (!p.spawned) continue;
        {
            var s = BinaryStream.init(block.allocator, null, null);
            defer s.deinit();
            const update = Protocol.UpdateBlockPacket{
                .position = block.position,
                .networkBlockId = network_id,
            };
            const serialized = update.serialize(&s) catch continue;
            p.network.sendPacket(p.connection, serialized) catch {};
        }
        {
            var s = BinaryStream.init(block.allocator, null, null);
            defer s.deinit();
            const sound = Protocol.LevelSoundEventPacket{
                .event = event,
                .position = .{
                    .x = @floatFromInt(block.position.x),
                    .y = @floatFromInt(block.position.y),
                    .z = @floatFromInt(block.position.z),
                },
                .data = new_perm.network_id,
                .actorIdentifier = "",
                .isBabyMob = false,
                .isGlobal = false,
            };
            const serialized = sound.serialize(&s) catch continue;
            p.network.sendPacket(p.connection, serialized) catch {};
        }
    }

    return false;
}

fn soundEvent(identifier: []const u8, open: bool) Protocol.LevelSoundEvent {
    if (std.mem.indexOf(u8, identifier, "trapdoor") != null)
        return if (open) .TrapdoorOpen else .TrapdoorClose;
    if (std.mem.indexOf(u8, identifier, "fence_gate") != null)
        return if (open) .FenceGateOpen else .FenceGateClose;
    return if (open) .DoorOpen else .DoorClose;
}

pub const OpenBitTrait = trait_mod.BlockTrait(State, .{
    .identifier = "open_bit",
    .onInteract = &onInteract,
});
