const std = @import("std");
const Protocol = @import("protocol");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");
const ItemType = @import("../../items/item-type.zig").ItemType;
const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const InventoryTrait = @import("../../entity/traits/inventory.zig");

pub fn register(registry: *CommandRegistry) !void {
    const cmd = try Command.init(
        registry.allocator,
        "give",
        "Give an item to a player",
        "conduit.command.give",
        &.{},
        @ptrCast(&handle),
    );
    try cmd.addOverload(&.{
        .{ .name = "player", .param_type = .Target, .optional = false },
        .{ .name = "itemName", .param_type = .String, .optional = false },
        .{ .name = "amount", .param_type = .Int, .optional = true },
        .{ .name = "data", .param_type = .Int, .optional = true },
    });
    try registry.registerCommand(cmd);
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /give <player> <item> [amount] [data]");
        return;
    }

    var arg_iter = std.mem.splitScalar(u8, trimmed, ' ');
    const target_name = arg_iter.next() orelse return;
    const item_name = arg_iter.next() orelse {
        ctx.sendOutput(false, "Usage: /give <player> <item> [amount] [data]");
        return;
    };
    const amount_str = arg_iter.next();
    const data_str = arg_iter.next();

    const targets = ctx.resolvePlayers(target_name) orelse {
        ctx.sendOutput(false, "Player not found");
        return;
    };

    var identifier_buf: [128]u8 = undefined;
    const identifier = if (std.mem.indexOf(u8, item_name, ":") != null)
        item_name
    else blk: {
        const written = std.fmt.bufPrint(&identifier_buf, "minecraft:{s}", .{item_name}) catch {
            ctx.sendOutput(false, "Item name too long");
            return;
        };
        break :blk written;
    };

    const item_type = ItemType.get(identifier) orelse {
        ctx.sendOutput(false, "Unknown item");
        return;
    };

    const amount: u16 = if (amount_str) |s| std.fmt.parseInt(u16, s, 10) catch 1 else 1;
    const data: u32 = if (data_str) |s| std.fmt.parseInt(u32, s, 10) catch 0 else 0;

    const short_name = if (std.mem.startsWith(u8, identifier, "minecraft:")) identifier[10..] else identifier;
    var given: u32 = 0;

    for (targets) |target| {
        const inv_state = target.entity.getTraitState(InventoryTrait.InventoryTrait) orelse continue;
        const item = ItemStack.init(ctx.allocator, item_type, .{ .stackSize = amount, .metadata = data });
        if (inv_state.container.addItem(item)) given += 1;
    }

    var buf: [128]u8 = undefined;
    if (targets.len == 1) {
        const msg = std.fmt.bufPrint(&buf, "Gave {d} {s} to {s}", .{ amount, short_name, targets[0].username }) catch return;
        ctx.sendOutput(true, msg);
    } else {
        const msg = std.fmt.bufPrint(&buf, "Gave {d} {s} to {d} players", .{ amount, short_name, given }) catch return;
        ctx.sendOutput(true, msg);
    }
}
