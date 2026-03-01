const std = @import("std");
const Raknet = @import("Raknet");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const NBT = @import("nbt");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const ItemType = @import("../../items/item-type.zig").ItemType;
const InventoryTrait = @import("../../entity/traits/inventory.zig").InventoryTrait;
const Inventory = @import("../../entity/traits/inventory.zig");

pub fn handleBlockPickRequest(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.BlockPickRequestPacket.deserialize(stream);

    const inv_state = player.entity.getTraitState(InventoryTrait) orelse {
        return;
    };

    const inv = &inv_state.container.base;

    const world = network.conduit.getWorld("world") orelse {
        Raknet.Logger.ERROR("Failed to get world", .{});
        return;
    };

    const dimension = world.getDimension("overworld") orelse {
        Raknet.Logger.ERROR("Failed to get dimension", .{});
        return;
    };

    const perm = dimension.getPermutation(packet.position, 0) catch |err| {
        Raknet.Logger.ERROR("Failed to get permutation: {any}", .{err});
        return;
    };

    if (std.mem.eql(u8, perm.identifier, "minecraft:air")) return;

    const item_type = ItemType.get(perm.identifier) orelse {
        return;
    };

    for (0..9) |i| {
        if (inv.getItem(@intCast(i))) |existing| {
            if (existing.item_type == item_type) {
                Inventory.setHeldItem(inv_state, &player.entity, @intCast(i));
                return;
            }
        }
    }

    const inv_size = inv.getSize();
    for (9..inv_size) |i| {
        if (inv.getItem(@intCast(i))) |existing| {
            if (existing.item_type == item_type) {
                const hotbar_slot = inv_state.selected_slot;
                inv.swapItems(hotbar_slot, @intCast(i), null);
                inv_state.container.updateSlot(hotbar_slot);
                inv_state.container.updateSlot(@intCast(i));
                Inventory.setHeldItem(inv_state, &player.entity, hotbar_slot);
                return;
            }
        }
    }

    if (player.gamemode != .Creative) return;

    var dest_slot: u8 = inv_state.selected_slot;
    for (0..9) |i| {
        if (inv.getItem(@intCast(i)) == null) {
            dest_slot = @intCast(i);
            break;
        }
    }

    var nbt_tag: ?NBT.CompoundTag = null;
    if (packet.add_user_data) {
        if (dimension.getBlockPtr(packet.position)) |block| {
            var tag = NBT.CompoundTag.init(network.allocator, null);
            block.fireEvent(.Serialize, .{&tag});
            if (tag.count() > 0) {
                nbt_tag = tag;
            } else {
                tag.deinit(network.allocator);
            }
        }
    }

    const item = ItemStack.init(player.entity.allocator, item_type, .{
        .stackSize = 64,
        .nbt = nbt_tag,
    });
    inv.setItem(dest_slot, item);
    inv_state.container.updateSlot(dest_slot);
    Inventory.setHeldItem(inv_state, &player.entity, dest_slot);
}
