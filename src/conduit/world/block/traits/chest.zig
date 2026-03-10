const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Block = @import("../block.zig").Block;
const Chunk = @import("../../chunk/chunk.zig").Chunk;
const Dimension = @import("../../dimension/dimension.zig").Dimension;
const CachedPacket = @import("../../dimension/dimension.zig").CachedPacket;
const chunkHash = @import("../../dimension/dimension.zig").chunkHash;
const BlockPermutation = @import("../block-permutation.zig").BlockPermutation;
const BlockState = @import("../block-permutation.zig").BlockState;
const BlockType = @import("../block-type.zig").BlockType;
const Player = @import("../../../player/player.zig").Player;
const Entity = @import("../../../entity/entity.zig").Entity;
const BlockContainer = @import("../../../container/block-container.zig").BlockContainer;
const CompoundTag = @import("nbt").CompoundTag;
const NBT = @import("nbt");
const trait_mod = @import("./trait.zig");
const serialization = @import("../../provider/serialization.zig");
const ItemStack = @import("../../../items/item-stack.zig").ItemStack;
const ItemType = @import("../../../items/item-type.zig").ItemType;
const Logger = @import("Raknet").Logger;

pub const State = struct {
    container: ?BlockContainer = null,
    pair_position: ?Protocol.BlockPosition = null,
    is_parent: bool = false,
};

fn resolvedPairPosition(state: *State, block: *Block) ?Protocol.BlockPosition {
    const pair = state.pair_position orelse return null;
    return .{
        .x = pair.x,
        .y = block.position.y,
        .z = pair.z,
    };
}

pub fn getResolvedPairPosition(block: *Block) ?Protocol.BlockPosition {
    const state = block.getTraitState(ChestTrait) orelse return null;
    return resolvedPairPosition(state, block);
}

pub fn restoreAdjacentPairing(block: *Block) void {
    const state = block.getTraitState(ChestTrait) orelse return;
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
        if (!std.mem.eql(u8, adj_block.getIdentifier(), block.getIdentifier())) continue;
        const adj_state = adj_block.getTraitState(ChestTrait) orelse continue;
        const adj_pair = resolvedPairPosition(adj_state, adj_block) orelse continue;

        if (adj_pair.x == block.position.x and adj_pair.y == block.position.y and adj_pair.z == block.position.z) {
            state.pair_position = adj_block.position;
            state.is_parent = !adj_state.is_parent;

            if (adj_state.is_parent) {
                if (adj_state.container) |*container| {
                    if (container.base.getSize() != 54) {
                        container.base.setSize(54) catch return;
                    }
                }
            } else if (state.container) |*container| {
                if (container.base.getSize() != 54) {
                    container.base.setSize(54) catch return;
                }
            }
            return;
        }
    }

    state.pair_position = null;
    state.is_parent = false;
    if (state.container) |*container| {
        if (container.base.getSize() != 27) {
            container.base.setSize(27) catch return;
        }
    }
    tryPairAdjacent(state, block);
}

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
        tag.set("pairlead", .{ .Int = @import("nbt").IntTag.init(if (state.is_parent) 1 else 0, null) }) catch {};
    }
}

fn onDeserialize(state: *State, tag: *const CompoundTag) void {
    const container = &(state.container orelse return);
    if (tag.get("pairx")) |pair_x_tag| {
        if (tag.get("pairz")) |pair_z_tag| {
            const pair_x = switch (pair_x_tag) {
                .Int => |t| t.value,
                else => null,
            };
            const pair_z = switch (pair_z_tag) {
                .Int => |t| t.value,
                else => null,
            };
            if (pair_x != null and pair_z != null) {
                state.pair_position = .{
                    .x = pair_x.?,
                    .y = 0,
                    .z = pair_z.?,
                };
            }
        }
    }
    if (tag.get("pairlead")) |pair_lead_tag| {
        const is_parent = switch (pair_lead_tag) {
            .Int => |t| t.value != 0,
            .Byte => |t| t.value != 0,
            else => null,
        };
        if (is_parent != null) {
            state.is_parent = is_parent.?;
            const expected_size: u32 = if (state.is_parent) 54 else 27;
            if (container.base.getSize() != expected_size) {
                container.base.setSize(expected_size) catch return;
            }
        }
    }
    if (tag.get("Items")) |items_tag| {
        switch (items_tag) {
            .List => |list| {
                serialization.deserializeContainer(container.base.allocator, &container.base, &list);
            },
            else => {},
        }
    }
}

fn ensurePairLink(state: *State, block: *Block) void {
    const pair_pos = resolvedPairPosition(state, block) orelse {
        tryPairAdjacent(state, block);
        return;
    };

    const paired_block = block.dimension.getBlockPtr(pair_pos) orelse return;
    const paired_state = paired_block.getTraitState(ChestTrait) orelse return;

    if (state.is_parent) {
        if (state.container) |*parent_container| {
            if (parent_container.base.getSize() != 54) {
                parent_container.base.setSize(54) catch return;
            }
            if (paired_state.container) |*child_container| {
                var slot: u32 = 0;
                while (slot < 27) : (slot += 1) {
                    if (child_container.base.storage[slot]) |item| {
                        parent_container.base.storage[slot + 27] = item;
                        child_container.base.storage[slot] = null;
                    }
                }
            }
        }
        paired_state.pair_position = block.position;
        paired_state.is_parent = false;
    } else {
        if (paired_state.container) |*parent_container| {
            if (parent_container.base.getSize() != 54) {
                parent_container.base.setSize(54) catch return;
            }
            if (state.container) |*child_container| {
                var slot: u32 = 0;
                while (slot < 27) : (slot += 1) {
                    if (child_container.base.storage[slot]) |item| {
                        parent_container.base.storage[slot + 27] = item;
                        child_container.base.storage[slot] = null;
                    }
                }
            }
        }
        paired_state.pair_position = block.position;
        paired_state.is_parent = true;
    }
}

fn sendActorData(block: *Block, player: *Player) void {
    const id = if (std.mem.eql(u8, block.getIdentifier(), "minecraft:trapped_chest")) "TrappedChest" else "Chest";
    var tag = @import("nbt").CompoundTag.init(block.allocator, null);
    defer tag.deinit(block.allocator);
    const id_str = block.allocator.dupe(u8, id) catch return;
    tag.set("id", .{ .String = NBT.StringTag.init(id_str, null) }) catch return;
    tag.set("x", .{ .Int = NBT.IntTag.init(block.position.x, null) }) catch return;
    tag.set("y", .{ .Int = NBT.IntTag.init(block.position.y, null) }) catch return;
    tag.set("z", .{ .Int = NBT.IntTag.init(block.position.z, null) }) catch return;
    block.fireEvent(.Serialize, .{&tag});
    var s = BinaryStream.init(block.allocator, null, null);
    defer s.deinit();
    const pkt = Protocol.BlockActorDataPacket{ .position = block.position, .nbt = tag };
    const serialized = pkt.serialize(&s, block.allocator) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};

    sendClientRefresh(block, player);
}

fn tileFixNetworkIds(block: *Block, position: Protocol.BlockPosition) ?[2]u32 {
    const target_block = block.dimension.getBlockPtr(position) orelse return null;
    const perm = target_block.getPermutation(0) catch return null;
    return .{ 0, @bitCast(perm.network_id) };
}

fn sendClientRefreshAt(block: *Block, position: Protocol.BlockPosition, player: *Player) void {
    const block_ids = tileFixNetworkIds(block, position) orelse return;

    {
        var s2 = BinaryStream.init(block.allocator, null, null);
        defer s2.deinit();
        const fix_air = Protocol.UpdateBlockPacket{ .position = position, .networkBlockId = block_ids[0] };
        const air_ser = fix_air.serialize(&s2) catch return;
        player.network.sendPacket(player.connection, air_ser) catch {};
    }
    {
        var s3 = BinaryStream.init(block.allocator, null, null);
        defer s3.deinit();
        const fix_real = Protocol.UpdateBlockPacket{ .position = position, .networkBlockId = block_ids[1] };
        const real_ser = fix_real.serialize(&s3) catch return;
        player.network.sendPacket(player.connection, real_ser) catch {};
    }
}

pub fn sendClientRefresh(block: *Block, player: *Player) void {
    sendClientRefreshAt(block, block.position, player);
}

fn onInteract(state: *State, block: *Block, player: *Player) bool {
    ensurePairLink(state, block);

    if (state.pair_position != null and !state.is_parent) {
        const parent_pos = resolvedPairPosition(state, block) orelse return true;
        const parent_block = block.dimension.getBlockPtr(parent_pos) orelse return true;
        const parent_state = parent_block.getTraitState(ChestTrait) orelse return true;
        return onInteract(parent_state, parent_block, player);
    }

    const container = &(state.container orelse return true);
    sendActorData(block, player);
    _ = container.show(player, block.position);
    sendBlockEvent(block, 1);
    sendSound(block, .ChestOpen);
    if (resolvedPairPosition(state, block)) |pair_pos| {
        sendBlockEventAt(block, pair_pos, 1);
    }
    return false;
}

fn onBreak(state: *State, block: *Block, _: ?*Player) bool {
    if (resolvedPairPosition(state, block)) |pair_pos| {
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
        else => {
            Logger.ERROR(
                "ChestTrait expected minecraft:cardinal_direction to be string, got '{s}' at ({d},{d},{d}) for {s}",
                .{ @tagName(direction), block.position.x, block.position.y, block.position.z, block.getIdentifier() },
            );
            return;
        },
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
        if (adj_dir != .string) {
            Logger.ERROR(
                "ChestTrait adjacent minecraft:cardinal_direction was '{s}' at ({d},{d},{d}) for {s}",
                .{ @tagName(adj_dir), adj_pos.x, adj_pos.y, adj_pos.z, adj_block.getIdentifier() },
            );
            continue;
        }
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

test "double chest preserves upper-half items when halves load in reverse order" {
    const allocator = std.testing.allocator;

    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();
    try BlockType.initRegistry(allocator);
    defer BlockType.deinitRegistry();
    trait_mod.initTraitRegistry(allocator);
    defer trait_mod.deinitTraitRegistry();
    try ItemType.initRegistry(allocator);
    defer ItemType.deinitRegistry();
    try ChestTrait.register();

    const air_type = try BlockType.init(allocator, "minecraft:air");
    try air_type.register();
    const air_state = BlockState.init(allocator);
    const air_perm = try BlockPermutation.init(allocator, 0, "minecraft:air", air_state);
    try air_perm.register();
    try air_type.addPermutation(air_perm);

    const chest_type = try BlockType.init(allocator, "minecraft:chest");
    try chest_type.register();

    var chest_state = BlockState.init(allocator);
    try chest_state.put(
        try allocator.dupe(u8, "minecraft:cardinal_direction"),
        .{ .string = try allocator.dupe(u8, "north") },
    );
    const chest_perm = try BlockPermutation.init(allocator, 1, "minecraft:chest", chest_state);
    try chest_perm.register();
    try chest_type.addPermutation(chest_perm);

    const test_item = try ItemType.init(
        allocator,
        try allocator.dupe(u8, "test:item"),
        1,
        64,
        true,
        try allocator.alloc([]const u8, 0),
        false,
        0,
        NBT.Tag{ .Compound = NBT.CompoundTag.init(allocator, null) },
    );
    try test_item.register();

    var dim = Dimension{
        .world = undefined,
        .allocator = allocator,
        .identifier = "test",
        .dimension_type = .Overworld,
        .chunks = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), *Chunk).init(allocator),
        .entities = std.AutoHashMap(i64, *Entity).init(allocator),
        .blocks = std.AutoHashMap(i64, *Block).init(allocator),
        .blocks_by_chunk = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), std.ArrayList(*Block)).init(allocator),
        .chunk_packet_cache = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), CachedPacket).init(allocator),
        .chunk_generations = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), u64).init(allocator),
        .pending_removals = std.ArrayList(i64){ .items = &.{}, .capacity = 0 },
        .spawn_position = .{ .x = 0, .y = 0, .z = 0 },
        .simulation_distance = 4,
        .generator = null,
    };
    defer dim.deinit();

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.init(allocator, 0, 0, .Overworld);
    try dim.chunks.put(chunkHash(0, 0), chunk);

    const left = Protocol.BlockPosition{ .x = 0, .y = 64, .z = 0 };
    const right = Protocol.BlockPosition{ .x = 1, .y = 64, .z = 0 };
    try chunk.setPermutation(left.x, left.y, left.z, chest_perm, 0);
    try chunk.setPermutation(right.x, right.y, right.z, chest_perm, 0);

    try trait_mod.applyTraitsForBlock(allocator, &dim, right);
    try trait_mod.applyTraitsForBlock(allocator, &dim, left);

    const saved_left = dim.getBlockPtr(left).?;
    const saved_left_state = saved_left.getTraitState(ChestTrait).?;
    try std.testing.expect(saved_left_state.is_parent);

    if (saved_left_state.container) |*container| {
        container.base.setItem(30, ItemStack.init(allocator, test_item, .{ .stackSize = 7 }));
    } else {
        return error.TestUnexpectedResult;
    }

    var left_tag = CompoundTag.init(allocator, null);
    defer left_tag.deinit(allocator);
    var right_tag = CompoundTag.init(allocator, null);
    defer right_tag.deinit(allocator);
    saved_left.fireEvent(.Serialize, .{&left_tag});
    dim.getBlockPtr(right).?.fireEvent(.Serialize, .{&right_tag});

    dim.removeBlock(left);
    dim.removeBlock(right);

    try trait_mod.applyTraitsForBlock(allocator, &dim, left);
    try trait_mod.applyTraitsForBlock(allocator, &dim, right);

    const loaded_left = dim.getBlockPtr(left).?;
    const loaded_right = dim.getBlockPtr(right).?;
    restoreAdjacentPairing(loaded_right);
    restoreAdjacentPairing(loaded_left);
    loaded_right.fireEvent(.Deserialize, .{&right_tag});
    loaded_left.fireEvent(.Deserialize, .{&left_tag});

    const loaded_left_state = loaded_left.getTraitState(ChestTrait).?;
    const loaded_right_state = loaded_right.getTraitState(ChestTrait).?;
    try std.testing.expect(loaded_left_state.is_parent);
    try std.testing.expect(!loaded_right_state.is_parent);
    try std.testing.expectEqual(@as(u32, 54), loaded_left_state.container.?.base.getSize());
    try std.testing.expectEqual(@as(u32, 27), loaded_right_state.container.?.base.getSize());
    try std.testing.expect(loaded_left_state.container.?.base.getItem(30) != null);
}

test "tile fix uses air then real block" {
    const allocator = std.testing.allocator;

    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();
    try BlockType.initRegistry(allocator);
    defer BlockType.deinitRegistry();
    trait_mod.initTraitRegistry(allocator);
    defer trait_mod.deinitTraitRegistry();
    try ChestTrait.register();

    const air_type = try BlockType.init(allocator, "minecraft:air");
    try air_type.register();
    const air_state = BlockState.init(allocator);
    const air_perm = try BlockPermutation.init(allocator, 0, "minecraft:air", air_state);
    try air_perm.register();
    try air_type.addPermutation(air_perm);

    const chest_type = try BlockType.init(allocator, "minecraft:chest");
    try chest_type.register();

    var chest_state = BlockState.init(allocator);
    try chest_state.put(
        try allocator.dupe(u8, "minecraft:cardinal_direction"),
        .{ .string = try allocator.dupe(u8, "north") },
    );
    const chest_perm = try BlockPermutation.init(allocator, 1, "minecraft:chest", chest_state);
    try chest_perm.register();
    try chest_type.addPermutation(chest_perm);

    var dim = Dimension{
        .world = undefined,
        .allocator = allocator,
        .identifier = "test",
        .dimension_type = .Overworld,
        .chunks = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), *Chunk).init(allocator),
        .entities = std.AutoHashMap(i64, *Entity).init(allocator),
        .blocks = std.AutoHashMap(i64, *Block).init(allocator),
        .blocks_by_chunk = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), std.ArrayList(*Block)).init(allocator),
        .chunk_packet_cache = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), CachedPacket).init(allocator),
        .chunk_generations = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), u64).init(allocator),
        .pending_removals = std.ArrayList(i64){ .items = &.{}, .capacity = 0 },
        .spawn_position = .{ .x = 0, .y = 0, .z = 0 },
        .simulation_distance = 4,
        .generator = null,
    };
    defer dim.deinit();

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.init(allocator, 0, 0, .Overworld);
    try dim.chunks.put(chunkHash(0, 0), chunk);

    const left = Protocol.BlockPosition{ .x = 0, .y = 64, .z = 0 };
    const right = Protocol.BlockPosition{ .x = 1, .y = 64, .z = 0 };
    try chunk.setPermutation(left.x, left.y, left.z, chest_perm, 0);
    try chunk.setPermutation(right.x, right.y, right.z, chest_perm, 0);

    try trait_mod.applyTraitsForBlock(allocator, &dim, right);
    try trait_mod.applyTraitsForBlock(allocator, &dim, left);

    const parent_block = dim.getBlockPtr(left).?;
    const parent_state = parent_block.getTraitState(ChestTrait).?;
    try std.testing.expect(parent_state.is_parent);

    const block_ids = tileFixNetworkIds(parent_block, left) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0), block_ids[0]);
    try std.testing.expectEqual(@as(u32, @bitCast(chest_perm.network_id)), block_ids[1]);
}

test "double chest serialization writes pairlead as int tag" {
    const allocator = std.testing.allocator;

    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();
    try BlockType.initRegistry(allocator);
    defer BlockType.deinitRegistry();
    trait_mod.initTraitRegistry(allocator);
    defer trait_mod.deinitTraitRegistry();
    try ChestTrait.register();

    const air_type = try BlockType.init(allocator, "minecraft:air");
    try air_type.register();
    const air_state = BlockState.init(allocator);
    const air_perm = try BlockPermutation.init(allocator, 0, "minecraft:air", air_state);
    try air_perm.register();
    try air_type.addPermutation(air_perm);

    const chest_type = try BlockType.init(allocator, "minecraft:chest");
    try chest_type.register();

    var chest_state = BlockState.init(allocator);
    try chest_state.put(
        try allocator.dupe(u8, "minecraft:cardinal_direction"),
        .{ .string = try allocator.dupe(u8, "north") },
    );
    const chest_perm = try BlockPermutation.init(allocator, 1, "minecraft:chest", chest_state);
    try chest_perm.register();
    try chest_type.addPermutation(chest_perm);

    var dim = Dimension{
        .world = undefined,
        .allocator = allocator,
        .identifier = "test",
        .dimension_type = .Overworld,
        .chunks = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), *Chunk).init(allocator),
        .entities = std.AutoHashMap(i64, *Entity).init(allocator),
        .blocks = std.AutoHashMap(i64, *Block).init(allocator),
        .blocks_by_chunk = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), std.ArrayList(*Block)).init(allocator),
        .chunk_packet_cache = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), CachedPacket).init(allocator),
        .chunk_generations = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), u64).init(allocator),
        .pending_removals = std.ArrayList(i64){ .items = &.{}, .capacity = 0 },
        .spawn_position = .{ .x = 0, .y = 0, .z = 0 },
        .simulation_distance = 4,
        .generator = null,
    };
    defer dim.deinit();

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.init(allocator, 0, 0, .Overworld);
    try dim.chunks.put(chunkHash(0, 0), chunk);

    const left = Protocol.BlockPosition{ .x = 0, .y = 64, .z = 0 };
    const right = Protocol.BlockPosition{ .x = 1, .y = 64, .z = 0 };
    try chunk.setPermutation(left.x, left.y, left.z, chest_perm, 0);
    try chunk.setPermutation(right.x, right.y, right.z, chest_perm, 0);

    try trait_mod.applyTraitsForBlock(allocator, &dim, right);
    try trait_mod.applyTraitsForBlock(allocator, &dim, left);

    const parent_block = dim.getBlockPtr(left).?;
    const parent_state = parent_block.getTraitState(ChestTrait).?;
    try std.testing.expect(parent_state.is_parent);

    var tag = CompoundTag.init(allocator, null);
    defer tag.deinit(allocator);
    parent_block.fireEvent(.Serialize, .{&tag});

    const pairlead = tag.get("pairlead") orelse return error.TestUnexpectedResult;
    try std.testing.expect(pairlead == .Int);
}

test "double chest preserves upper-half items across repeated unload cycles" {
    const allocator = std.testing.allocator;

    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();
    try BlockType.initRegistry(allocator);
    defer BlockType.deinitRegistry();
    trait_mod.initTraitRegistry(allocator);
    defer trait_mod.deinitTraitRegistry();
    try ItemType.initRegistry(allocator);
    defer ItemType.deinitRegistry();
    try ChestTrait.register();

    const air_type = try BlockType.init(allocator, "minecraft:air");
    try air_type.register();
    const air_state = BlockState.init(allocator);
    const air_perm = try BlockPermutation.init(allocator, 0, "minecraft:air", air_state);
    try air_perm.register();
    try air_type.addPermutation(air_perm);

    const chest_type = try BlockType.init(allocator, "minecraft:chest");
    try chest_type.register();

    var chest_state = BlockState.init(allocator);
    try chest_state.put(
        try allocator.dupe(u8, "minecraft:cardinal_direction"),
        .{ .string = try allocator.dupe(u8, "north") },
    );
    const chest_perm = try BlockPermutation.init(allocator, 1, "minecraft:chest", chest_state);
    try chest_perm.register();
    try chest_type.addPermutation(chest_perm);

    const test_item = try ItemType.init(
        allocator,
        try allocator.dupe(u8, "test:item"),
        1,
        64,
        true,
        try allocator.alloc([]const u8, 0),
        false,
        0,
        NBT.Tag{ .Compound = NBT.CompoundTag.init(allocator, null) },
    );
    try test_item.register();

    var dim = Dimension{
        .world = undefined,
        .allocator = allocator,
        .identifier = "test",
        .dimension_type = .Overworld,
        .chunks = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), *Chunk).init(allocator),
        .entities = std.AutoHashMap(i64, *Entity).init(allocator),
        .blocks = std.AutoHashMap(i64, *Block).init(allocator),
        .blocks_by_chunk = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), std.ArrayList(*Block)).init(allocator),
        .chunk_packet_cache = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), CachedPacket).init(allocator),
        .chunk_generations = std.AutoHashMap(@TypeOf(chunkHash(0, 0)), u64).init(allocator),
        .pending_removals = std.ArrayList(i64){ .items = &.{}, .capacity = 0 },
        .spawn_position = .{ .x = 0, .y = 0, .z = 0 },
        .simulation_distance = 4,
        .generator = null,
    };
    defer dim.deinit();

    const chunk = try allocator.create(Chunk);
    chunk.* = Chunk.init(allocator, 0, 0, .Overworld);
    try dim.chunks.put(chunkHash(0, 0), chunk);

    const left = Protocol.BlockPosition{ .x = 0, .y = 64, .z = 0 };
    const right = Protocol.BlockPosition{ .x = 1, .y = 64, .z = 0 };
    try chunk.setPermutation(left.x, left.y, left.z, chest_perm, 0);
    try chunk.setPermutation(right.x, right.y, right.z, chest_perm, 0);

    try trait_mod.applyTraitsForBlock(allocator, &dim, right);
    try trait_mod.applyTraitsForBlock(allocator, &dim, left);

    const initial_left = dim.getBlockPtr(left).?;
    const initial_left_state = initial_left.getTraitState(ChestTrait).?;
    try std.testing.expect(initial_left_state.is_parent);

    if (initial_left_state.container) |*container| {
        container.base.setItem(30, ItemStack.init(allocator, test_item, .{ .stackSize = 7 }));
    } else {
        return error.TestUnexpectedResult;
    }

    var cycle: usize = 0;
    while (cycle < 5) : (cycle += 1) {
        var left_tag = CompoundTag.init(allocator, null);
        defer left_tag.deinit(allocator);
        var right_tag = CompoundTag.init(allocator, null);
        defer right_tag.deinit(allocator);

        dim.getBlockPtr(left).?.fireEvent(.Serialize, .{&left_tag});
        dim.getBlockPtr(right).?.fireEvent(.Serialize, .{&right_tag});

        dim.removeBlock(left);
        dim.removeBlock(right);

        if (cycle % 2 == 0) {
            try trait_mod.applyTraitsForBlock(allocator, &dim, right);
            try trait_mod.applyTraitsForBlock(allocator, &dim, left);
        } else {
            try trait_mod.applyTraitsForBlock(allocator, &dim, left);
            try trait_mod.applyTraitsForBlock(allocator, &dim, right);
        }

        const loaded_left = dim.getBlockPtr(left).?;
        const loaded_right = dim.getBlockPtr(right).?;

        restoreAdjacentPairing(loaded_right);
        restoreAdjacentPairing(loaded_left);

        if (cycle % 2 == 0) {
            loaded_right.fireEvent(.Deserialize, .{&right_tag});
            loaded_left.fireEvent(.Deserialize, .{&left_tag});
        } else {
            loaded_left.fireEvent(.Deserialize, .{&left_tag});
            loaded_right.fireEvent(.Deserialize, .{&right_tag});
        }

        const loaded_left_state = loaded_left.getTraitState(ChestTrait).?;
        const loaded_right_state = loaded_right.getTraitState(ChestTrait).?;
        try std.testing.expect(loaded_left_state.is_parent);
        try std.testing.expect(!loaded_right_state.is_parent);
        try std.testing.expectEqual(@as(u32, 54), loaded_left_state.container.?.base.getSize());
        try std.testing.expectEqual(@as(u32, 27), loaded_right_state.container.?.base.getSize());

        const item = loaded_left_state.container.?.base.getItem(30) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(u16, 7), item.stackSize);
    }
}
