const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Container = @import("../../container/container.zig").Container;
const InventoryTrait = @import("../../entity/traits/inventory.zig").InventoryTrait;
const CursorTrait = @import("../../entity/traits/cursor.zig").CursorTrait;
const ItemType = @import("../../items/item-type.zig").ItemType;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const PlayerMath = @import("../../player/player.zig");

fn resolveContainer(
    inv_state: *InventoryTrait.TraitState,
    cursor_state: *CursorTrait.TraitState,
    container_name: Protocol.ContainerName,
    player: *@import("../../player/player.zig").Player,
) ?*Container {
    return switch (container_name) {
        .Hotbar, .Inventory, .HotbarAndInventory => &inv_state.container.base,
        .Cursor => &cursor_state.container.base,
        .Container, .Barrel, .Shulker => player.opened_container,
        else => null,
    };
}

fn resolveTransferContainer(
    inv_state: *InventoryTrait.TraitState,
    cursor_state: *CursorTrait.TraitState,
    container_name: Protocol.ContainerName,
    player: *@import("../../player/player.zig").Player,
) ?*Container {
    return switch (container_name) {
        .CreativeOutput => &cursor_state.container.base,
        else => resolveContainer(inv_state, cursor_state, container_name, player),
    };
}

fn canMergeStacks(a: *const ItemStack, b: *const ItemStack) bool {
    return a.item_type.stackable and
        a.isStackCompatible(b) and
        b.stackSize < b.item_type.max_stack_size;
}

fn applyTransferAction(src: *Container, source_slot: u32, dst: *Container, destination_slot: u32, count: u16) !void {
    const item = src.takeItem(source_slot, count) orelse return error.TransferFailed;

    if (dst.getItemMut(destination_slot)) |existing| {
        if (canMergeStacks(&item, existing)) {
            const space = existing.item_type.max_stack_size - existing.stackSize;
            const to_add = @min(space, item.stackSize);
            existing.stackSize += to_add;
            dst.updateSlot(destination_slot);

            const remaining = item.stackSize - to_add;
            if (remaining > 0) {
                var remainder = item;
                remainder.stackSize = remaining;
                src.setItem(source_slot, remainder);
            } else {
                var consumed = item;
                consumed.deinit();
            }

            return;
        }

        src.setItem(source_slot, item);
        dst.swapItems(destination_slot, source_slot, src);
        return;
    }

    dst.setItem(destination_slot, item);
}

fn applyDropAction(src: *Container, source_slot: u32, count: u16) !ItemStack {
    const item = src.getItem(source_slot) orelse return error.DropFailed;
    const drop_count = @min(if (count == 0) @as(u16, 1) else count, item.stackSize);
    return src.takeItem(source_slot, drop_count) orelse error.DropFailed;
}

fn spawnDroppedItem(player: *@import("../../player/player.zig").Player, item: ItemStack) void {
    const dimension = player.entity.dimension orelse return;
    const spawn_pos = playerDropSpawnPosition(player.entity.position);
    const throw_vel = PlayerMath.playerDropVelocity(player.entity.rotation);
    _ = dimension.spawnItemStackEntity(item, spawn_pos, 40, throw_vel) catch {};
}

fn playerDropSpawnPosition(pos: Protocol.Vector3f) Protocol.Vector3f {
    return PlayerMath.playerDropSpawnPosition(pos);
}

// TODO: Handle inventory transactions more accordingly to avoid client predicted issues

pub fn handleItemStackRequest(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    var packet = try Protocol.ItemStackRequestPacket.deserialize(stream);
    defer packet.deinit(network.allocator);

    const inv_state = player.entity.getTraitState(InventoryTrait) orelse return;
    const cursor_state = player.entity.getTraitState(CursorTrait) orelse return;

    for (packet.requests) |request| {
        for (request.actions) |action| {
            // Raknet.Logger.WARN("{any}", .{action});
            switch (action) {
                .take, .place => |t| {
                    const src = resolveTransferContainer(inv_state, cursor_state, t.source.container.identifier, player) orelse continue;
                    const dst = resolveTransferContainer(inv_state, cursor_state, t.destination.container.identifier, player) orelse continue;
                    applyTransferAction(src, t.source.slot, dst, t.destination.slot, t.count) catch continue;
                },
                .swap => |s| {
                    const src = resolveContainer(inv_state, cursor_state, s.source.container.identifier, player) orelse continue;
                    const dst = resolveContainer(inv_state, cursor_state, s.destination.container.identifier, player) orelse continue;
                    src.swapItems(s.source.slot, s.destination.slot, dst);
                },
                .drop => |d| {
                    const src = resolveContainer(inv_state, cursor_state, d.source.container.identifier, player) orelse continue;
                    const dropped = applyDropAction(src, d.source.slot, d.count) catch continue;
                    spawnDroppedItem(player, dropped);
                },
                .destroy, .consume => |d| {
                    const src = resolveContainer(inv_state, cursor_state, d.source.container.identifier, player) orelse continue;
                    src.clearSlot(d.source.slot);
                },
                .craftCreative => |c| {
                    const cc = network.conduit.creative_content orelse continue;
                    const network_id = cc.getNetworkIdByCreativeIndex(c.creativeItemNetworkId) orelse continue;
                    const item_type = ItemType.getByNetworkId(network_id) orelse continue;
                    const item = ItemStack.init(player.entity.allocator, item_type, .{
                        .stackSize = item_type.max_stack_size,
                    });
                    cursor_state.container.base.setItem(0, item);
                },
                .craftResultsDeprecated => {},
                else => |a| {
                    Raknet.Logger.WARN("Unhandeled action {any}", .{a});
                },
            }
        }

        inv_state.container.sendContentUpdate();
        cursor_state.container.sendContentUpdate();
        if (player.opened_container) |opened| opened.update();
    }
}

test "creative output resolves to cursor for transfer handling" {
    const allocator = std.testing.allocator;

    var inv_base = try Container.init(allocator, .Inventory, 36);
    defer inv_base.deinit();
    var cursor_base = try Container.init(allocator, .Inventory, 1);
    defer cursor_base.deinit();

    var inv_state = InventoryTrait.TraitState{
        .container = .{
            .base = inv_base,
            .owner = undefined,
        },
        .selected_slot = 0,
        .opened = false,
    };
    var cursor_state = CursorTrait.TraitState{
        .container = .{
            .base = cursor_base,
            .owner = undefined,
        },
    };
    var player: @import("../../player/player.zig").Player = undefined;

    const resolved = resolveTransferContainer(&inv_state, &cursor_state, .CreativeOutput, &player) orelse {
        return error.TestUnexpectedResult;
    };

    try std.testing.expect(resolved == &cursor_state.container.base);
}

test "transfer action merges matching stacks into occupied destination" {
    const allocator = std.testing.allocator;

    var src = try Container.init(allocator, .Inventory, 36);
    defer src.deinit();
    var dst = try Container.init(allocator, .Inventory, 1);
    defer dst.deinit();

    const stone = ItemType.get("minecraft:stone") orelse return error.TestUnexpectedResult;

    src.setItem(5, ItemStack.init(allocator, stone, .{ .stackSize = 1 }));
    dst.setItem(0, ItemStack.init(allocator, stone, .{ .stackSize = 10 }));

    try applyTransferAction(&src, 5, &dst, 0, 1);

    try std.testing.expect(src.getItem(5) == null);
    const cursor = dst.getItem(0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 11), cursor.stackSize);
}

test "drop action removes only requested amount from source stack" {
    const allocator = std.testing.allocator;

    var src = try Container.init(allocator, .Inventory, 36);
    defer src.deinit();

    const stone = ItemType.get("minecraft:stone") orelse return error.TestUnexpectedResult;
    src.setItem(9, ItemStack.init(allocator, stone, .{ .stackSize = 32 }));

    var dropped = try applyDropAction(&src, 9, 1);
    defer dropped.deinit();

    try std.testing.expectEqual(stone, dropped.item_type);
    try std.testing.expectEqual(@as(u16, 1), dropped.stackSize);
    const remaining = src.getItem(9) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 31), remaining.stackSize);
}

test "drop spawn position is relative to player feet, not above head" {
    const pos = Protocol.Vector3f.init(4, 65.62, -2);
    const drop_pos = playerDropSpawnPosition(pos);

    try std.testing.expectEqual(@as(f32, 4), drop_pos.x);
    try std.testing.expectEqual(@as(f32, 65.3), drop_pos.y);
    try std.testing.expectEqual(@as(f32, -2), drop_pos.z);
}
