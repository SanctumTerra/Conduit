const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Block = @import("../block.zig").Block;
const BlockPermutation = @import("../block-permutation.zig").BlockPermutation;
const BlockType = @import("../block-type.zig").BlockType;
const BlockState = @import("../block-permutation.zig").BlockState;
const Player = @import("../../../player/player.zig").Player;
const BlockContainer = @import("../../../container/block-container.zig").BlockContainer;
const trait_mod = @import("./trait.zig");
const CompoundTag = @import("nbt").CompoundTag;
const serialization = @import("../../provider/serialization.zig");
const Logger = @import("Raknet").Logger;

pub const State = struct {
    container: ?BlockContainer = null,
};

fn onAttach(state: *State, block: *Block) void {
    if (state.container == null) {
        state.container = BlockContainer.init(block.allocator, .Container, 27) catch return;
    }
}

fn onDetach(state: *State, _: *Block) void {
    if (state.container) |*c| c.deinit();
    state.container = null;
}

fn onSerialize(state: *State, tag: *CompoundTag) void {
    const container = &(state.container orelse return);
    const list = serialization.serializeContainer(tag.allocator, &container.base) catch return;
    tag.set("Items", .{ .List = list }) catch {};
}

fn onDeserialize(state: *State, tag: *const CompoundTag) void {
    const container = &(state.container orelse return);
    const items_tag = tag.get("Items") orelse return;
    switch (items_tag) {
        .List => |list| {
            serialization.deserializeContainer(container.base.allocator, &container.base, &list);
        },
        else => {},
    }
}

fn sendActorData(block: *Block, player: *Player) void {
    const NBT = @import("nbt");
    var tag = CompoundTag.init(block.allocator, null);
    defer tag.deinit(block.allocator);
    const id_str = block.allocator.dupe(u8, "Barrel") catch return;
    tag.set("id", .{ .String = NBT.StringTag.init(id_str, null) }) catch return;
    tag.set("x", .{ .Int = NBT.IntTag.init(block.position.x, null) }) catch return;
    tag.set("y", .{ .Int = NBT.IntTag.init(block.position.y, null) }) catch return;
    tag.set("z", .{ .Int = NBT.IntTag.init(block.position.z, null) }) catch return;
    var s = BinaryStream.init(block.allocator, null, null);
    defer s.deinit();
    const pkt = Protocol.BlockActorDataPacket{ .position = block.position, .nbt = tag };
    const serialized = pkt.serialize(&s, block.allocator) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};

    {
        var s2 = BinaryStream.init(block.allocator, null, null);
        defer s2.deinit();
        const fix_air = Protocol.UpdateBlockPacket{ .position = block.position, .networkBlockId = 0 };
        const air_ser = fix_air.serialize(&s2) catch return;
        player.network.sendPacket(player.connection, air_ser) catch {};
    }
    {
        const perm = block.getPermutation(0) catch return;
        const real_id: u32 = @bitCast(perm.network_id);
        var s3 = BinaryStream.init(block.allocator, null, null);
        defer s3.deinit();
        const fix_real = Protocol.UpdateBlockPacket{ .position = block.position, .networkBlockId = real_id };
        const real_ser = fix_real.serialize(&s3) catch return;
        player.network.sendPacket(player.connection, real_ser) catch {};
    }
}

fn onInteract(state: *State, block: *Block, player: *Player) bool {
    const container = &(state.container orelse return true);
    sendActorData(block, player);
    _ = container.show(player, block.position);

    setOpenBit(block, true);
    sendSound(block, .BarrelOpen);
    return false;
}

fn onBreak(state: *State, block: *Block, _: ?*Player) bool {
    if (state.container) |*container| {
        var iter = container.base.occupants.iterator();
        while (iter.next()) |entry| {
            container.base.close(entry.key_ptr.*, true);
        }
    }
    setOpenBit(block, false);
    sendSound(block, .BarrelClose);
    return true;
}

fn setOpenBit(block: *Block, open: bool) void {
    const perm = block.getPermutation(0) catch return;
    if (!perm.state.contains("open_bit")) return;

    const current = perm.state.get("open_bit") orelse return;
    const current_val = switch (current) {
        .boolean => |b| b,
        else => return,
    };
    if (current_val == open) return;

    const block_type = BlockType.get(perm.identifier) orelse return;
    var state = BlockState.init(block.allocator);
    defer state.deinit();

    var iter = perm.state.iterator();
    while (iter.next()) |entry| {
        state.put(entry.key_ptr.*, entry.value_ptr.*) catch return;
    }
    state.put("open_bit", .{ .boolean = open }) catch return;

    const new_perm = block_type.getPermutation(state);
    block.setPermutation(new_perm, 0) catch {};

    const conduit = block.dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();
    const network_id: u32 = @bitCast(new_perm.network_id);
    for (snapshots) |p| {
        if (!p.spawned) continue;
        var s = BinaryStream.init(block.allocator, null, null);
        defer s.deinit();
        const update = Protocol.UpdateBlockPacket{
            .position = block.position,
            .networkBlockId = network_id,
        };
        const serialized = update.serialize(&s) catch continue;
        p.network.sendPacket(p.connection, serialized) catch {};
    }
}

fn sendSound(block: *Block, event: Protocol.LevelSoundEvent) void {
    const conduit = block.dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();
    const perm = block.getPermutation(0) catch return;

    for (snapshots) |p| {
        if (!p.spawned) continue;
        var s = BinaryStream.init(block.allocator, null, null);
        defer s.deinit();
        const packet = Protocol.LevelSoundEventPacket{
            .event = event,
            .position = .{
                .x = @floatFromInt(block.position.x),
                .y = @floatFromInt(block.position.y),
                .z = @floatFromInt(block.position.z),
            },
            .data = perm.network_id,
            .actorIdentifier = "",
            .isBabyMob = false,
            .isGlobal = false,
        };
        const serialized = packet.serialize(&s) catch continue;
        p.network.sendPacket(p.connection, serialized) catch {};
    }
}

pub const BarrelTrait = trait_mod.BlockTrait(State, .{
    .identifier = "barrel",
    .blocks = &.{
        "minecraft:barrel",
    },
    .onAttach = &onAttach,
    .onDetach = &onDetach,
    .onInteract = &onInteract,
    .onBreak = &onBreak,
    .onSerialize = &onSerialize,
    .onDeserialize = &onDeserialize,
});
