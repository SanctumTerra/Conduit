const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Block = @import("../block.zig").Block;
const Player = @import("../../../player/player.zig").Player;
const BlockContainer = @import("../../../container/block-container.zig").BlockContainer;
const CompoundTag = @import("nbt").CompoundTag;
const trait_mod = @import("./trait.zig");
const serialization = @import("../../provider/serialization.zig");

pub const State = struct {
    container: ?BlockContainer = null,
    pair_position: ?Protocol.BlockPosition = null,
    is_parent: bool = false,
};

fn onAttach(state: *State, block: *Block) void {
    if (state.container == null) {
        state.container = BlockContainer.init(block.allocator, .Container, 27) catch return;
    }
    tryPairAdjacent(state, block);
}

fn onDetach(state: *State, _: *Block) void {
    if (state.container) |*c| c.deinit();
    state.container = null;
}

fn onSerialize(state: *State, tag: *CompoundTag) void {
    const container = &(state.container orelse return);
    const list = serialization.serializeContainer(tag.allocator, &container.base) catch return;
    tag.set("Items", .{ .List = list }) catch {};
    if (state.pair_position) |pair| {
        tag.set("pairx", .{ .Int = @import("nbt").IntTag.init(pair.x, null) }) catch {};
        tag.set("pairz", .{ .Int = @import("nbt").IntTag.init(pair.z, null) }) catch {};
        tag.set("pairlead", .{ .Byte = @import("nbt").ByteTag.init(if (state.is_parent) 1 else 0, null) }) catch {};
    }
}

fn onDeserialize(state: *State, tag: *const CompoundTag) void {
    const container = &(state.container orelse return);
    const items_tag = tag.get("Items") orelse return;
    switch (items_tag) {
        .List => |list| serialization.deserializeContainer(container.base.allocator, &container.base, &list),
        else => {},
    }
}

fn onInteract(state: *State, block: *Block, player: *Player) bool {
    if (state.pair_position != null and !state.is_parent) {
        const parent_block = block.dimension.getBlockPtr(state.pair_position.?) orelse return true;
        const parent_state = parent_block.getTraitState(ChestTrait) orelse return true;
        return onInteract(parent_state, parent_block, player);
    }

    const container = &(state.container orelse return true);
    _ = container.show(player, block.position);
    sendBlockEvent(block, 1);
    sendSound(block, .ChestOpen);
    if (state.pair_position) |pair_pos| {
        sendBlockEventAt(block, pair_pos, 1);
    }
    return false;
}

fn onBreak(state: *State, block: *Block, _: ?*Player) bool {
    if (state.pair_position) |pair_pos| {
        if (state.is_parent) {
            if (state.container) |*container| {
                var iter = container.base.occupants.iterator();
                while (iter.next()) |entry| {
                    container.base.close(entry.key_ptr.*, true);
                }
            }
            if (block.dimension.getBlockPtr(pair_pos)) |paired_block| {
                if (paired_block.getTraitState(ChestTrait)) |paired_state| {
                    if (state.container) |*parent_container| {
                        if (paired_state.container) |*child_container| {
                            var slot: u32 = 27;
                            while (slot < parent_container.base.getSize()) : (slot += 1) {
                                if (parent_container.base.storage[slot]) |item| {
                                    const target = slot - 27;
                                    child_container.base.storage[target] = item;
                                    parent_container.base.storage[slot] = null;
                                }
                            }
                        }
                        parent_container.base.setSize(27) catch {};
                    }
                    paired_state.pair_position = null;
                    paired_state.is_parent = false;
                }
            }
        } else {
            if (block.dimension.getBlockPtr(pair_pos)) |paired_block| {
                if (paired_block.getTraitState(ChestTrait)) |paired_state| {
                    if (paired_state.container) |*parent_container| {
                        var iter = parent_container.base.occupants.iterator();
                        while (iter.next()) |entry| {
                            parent_container.base.close(entry.key_ptr.*, true);
                        }
                        if (state.container) |*child_container| {
                            var slot: u32 = 27;
                            while (slot < parent_container.base.getSize()) : (slot += 1) {
                                if (parent_container.base.storage[slot]) |item| {
                                    const target = slot - 27;
                                    child_container.base.storage[target] = item;
                                    parent_container.base.storage[slot] = null;
                                }
                            }
                        }
                        parent_container.base.setSize(27) catch {};
                    }
                    paired_state.pair_position = null;
                    paired_state.is_parent = false;
                }
            }
        }
    } else {
        if (state.container) |*container| {
            var iter = container.base.occupants.iterator();
            while (iter.next()) |entry| {
                container.base.close(entry.key_ptr.*, true);
            }
        }
    }
    sendBlockEvent(block, 0);
    sendSound(block, .ChestClosed);
    return true;
}

fn tryPairAdjacent(state: *State, block: *Block) void {
    const perm = block.getPermutation(0) catch return;
    const direction = perm.state.get("minecraft:cardinal_direction") orelse return;

    const offsets: [2][2]i32 = switch (direction) {
        .string => |dir| blk: {
            if (std.mem.eql(u8, dir, "north") or std.mem.eql(u8, dir, "south")) {
                break :blk .{ .{ -1, 0 }, .{ 1, 0 } };
            } else {
                break :blk .{ .{ 0, -1 }, .{ 0, 1 } };
            }
        },
        else => return,
    };

    for (offsets) |off| {
        const adj_pos = Protocol.BlockPosition{
            .x = block.position.x + off[0],
            .y = block.position.y,
            .z = block.position.z + off[1],
        };
        const adj_block = block.dimension.getBlockPtr(adj_pos) orelse continue;
        const adj_state = adj_block.getTraitState(ChestTrait) orelse continue;
        if (adj_state.pair_position != null) continue;

        if (!std.mem.eql(u8, adj_block.getIdentifier(), block.getIdentifier())) continue;

        const adj_perm = adj_block.getPermutation(0) catch continue;
        const adj_dir = adj_perm.state.get("minecraft:cardinal_direction") orelse continue;
        if (!direction.eql(adj_dir)) break;

        state.pair_position = adj_pos;
        state.is_parent = true;
        adj_state.pair_position = block.position;
        adj_state.is_parent = false;

        if (state.container) |*container| {
            container.base.setSize(54) catch return;
            if (adj_state.container) |*adj_container| {
                var slot: u32 = 0;
                while (slot < 27) : (slot += 1) {
                    if (adj_container.base.storage[slot]) |item| {
                        container.base.storage[slot + 27] = item;
                        adj_container.base.storage[slot] = null;
                    }
                }
            }
        }
        return;
    }
}

fn sendBlockEvent(block: *Block, data: i32) void {
    sendBlockEventAt(block, block.position, data);
}

fn sendBlockEventAt(block: *Block, position: Protocol.BlockPosition, data: i32) void {
    const conduit = block.dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();

    for (snapshots) |p| {
        if (!p.spawned) continue;
        var stream = BinaryStream.init(block.allocator, null, null);
        defer stream.deinit();
        const packet = Protocol.BlockEventPacket{
            .position = position,
            .event_type = .ChangeState,
            .data = data,
        };
        const serialized = packet.serialize(&stream) catch continue;
        p.network.sendPacket(p.connection, serialized) catch {};
    }
}

fn sendSound(block: *Block, event: Protocol.LevelSoundEvent) void {
    const conduit = block.dimension.world.conduit;
    const snapshots = conduit.getPlayerSnapshots();
    const perm = block.getPermutation(0) catch return;
    const network_id: i32 = perm.network_id;

    for (snapshots) |p| {
        if (!p.spawned) continue;
        var stream = BinaryStream.init(block.allocator, null, null);
        defer stream.deinit();
        const packet = Protocol.LevelSoundEventPacket{
            .event = event,
            .position = .{
                .x = @floatFromInt(block.position.x),
                .y = @floatFromInt(block.position.y),
                .z = @floatFromInt(block.position.z),
            },
            .data = network_id,
            .actorIdentifier = "",
            .isBabyMob = false,
            .isGlobal = false,
        };
        const serialized = packet.serialize(&stream) catch continue;
        p.network.sendPacket(p.connection, serialized) catch {};
    }
}

pub const ChestTrait = trait_mod.BlockTrait(State, .{
    .identifier = "chest",
    .blocks = &.{
        "minecraft:chest",
        "minecraft:trapped_chest",
    },
    .onAttach = &onAttach,
    .onDetach = &onDetach,
    .onInteract = &onInteract,
    .onBreak = &onBreak,
    .onSerialize = &onSerialize,
    .onDeserialize = &onDeserialize,
});
