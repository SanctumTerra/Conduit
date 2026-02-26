const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Container = @import("../../container/container.zig").Container;
const InventoryTrait = @import("../../entity/traits/inventory.zig").InventoryTrait;
const CursorTrait = @import("../../entity/traits/cursor.zig").CursorTrait;
const ItemType = @import("../../items/item-type.zig").ItemType;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;

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
            switch (action) {
                .take, .place => |t| {
                    const src = resolveContainer(inv_state, cursor_state, t.source.container.identifier, player) orelse continue;
                    const dst = resolveContainer(inv_state, cursor_state, t.destination.container.identifier, player) orelse continue;

                    const item = src.takeItem(t.source.slot, t.count) orelse continue;

                    const existing = dst.getItem(t.destination.slot);
                    if (existing != null) {
                        dst.swapItems(t.destination.slot, t.source.slot, src);
                    }
                    dst.setItem(t.destination.slot, item);
                },
                .swap => |s| {
                    const src = resolveContainer(inv_state, cursor_state, s.source.container.identifier, player) orelse continue;
                    const dst = resolveContainer(inv_state, cursor_state, s.destination.container.identifier, player) orelse continue;
                    src.swapItems(s.source.slot, s.destination.slot, dst);
                },
                .drop => |d| {
                    const src = resolveContainer(inv_state, cursor_state, d.source.container.identifier, player) orelse continue;
                    src.clearSlot(d.source.slot);
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
