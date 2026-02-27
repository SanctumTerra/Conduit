const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Raknet = @import("Raknet");
const Command = @import("../command.zig").Command;
const SubCommand = @import("../command.zig").SubCommand;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");

pub fn register(registry: *CommandRegistry) !void {
    const cmd = try Command.init(
        registry.allocator,
        "ban",
        "Ban or unban a player",
        "conduit.command.ban",
        &.{},
        @ptrCast(&handleBan),
    );
    try cmd.addOverload(&.{
        .{ .name = "player", .param_type = .Target, .optional = false },
        .{ .name = "reason", .param_type = .Message, .optional = true },
    });

    const unban_sub = try registry.allocator.create(SubCommand);
    unban_sub.* = .{
        .name = "remove",
        .aliases = &.{},
        .params = &.{
            .{ .name = "player", .param_type = .String, .optional = false },
        },
        .handler = @ptrCast(&handleUnban),
    };
    try cmd.registerSubCommand(unban_sub);

    const list_sub = try registry.allocator.create(SubCommand);
    list_sub.* = .{
        .name = "list",
        .aliases = &.{},
        .params = &.{},
        .handler = @ptrCast(&handleList),
    };
    try cmd.registerSubCommand(list_sub);

    try registry.registerCommand(cmd);
}

fn handleBan(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /ban <player> [reason]");
        return;
    }

    const space_idx = std.mem.indexOfScalar(u8, trimmed, ' ');
    const target_name = if (space_idx) |idx| trimmed[0..idx] else trimmed;
    const reason = if (space_idx) |idx| std.mem.trim(u8, trimmed[idx + 1 ..], " ") else "Banned by an operator.";

    var ban_mgr = &ctx.network.conduit.ban_manager;

    if (ban_mgr.isBanned(target_name)) {
        ctx.sendOutput(false, "Player is already banned");
        return;
    }

    if (ctx.resolvePlayer(target_name)) |player| {
        ban_mgr.ban(player.uuid, player.username, ctx.player.username, reason) catch {
            ctx.sendOutput(false, "Failed to ban player");
            return;
        };
        Raknet.Logger.INFO("{s} banned {s}: {s}", .{ ctx.player.username, player.username, reason });

        var stream = BinaryStream.init(ctx.allocator, null, null);
        defer stream.deinit();
        var disconnect = Protocol.DisconnectPacket{
            .hideScreen = false,
            .reason = .Kicked,
            .message = reason,
            .filtered = reason,
        };
        const serialized = disconnect.serialize(&stream) catch return;
        ctx.network.sendImmediate(player.connection, serialized) catch {};
        player.connection.active = false;
    } else {
        ban_mgr.ban("", target_name, ctx.player.username, reason) catch {
            ctx.sendOutput(false, "Failed to ban player");
            return;
        };
    }

    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Banned {s}", .{target_name}) catch return;
    ctx.sendOutput(true, msg);
}

fn handleUnban(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /ban remove <player>");
        return;
    }

    var ban_mgr = &ctx.network.conduit.ban_manager;
    if (ban_mgr.unban(trimmed)) {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Unbanned {s}", .{trimmed}) catch return;
        ctx.sendOutput(true, msg);
    } else {
        ctx.sendOutput(false, "Player is not banned");
    }
}

fn handleList(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const ban_mgr = &ctx.network.conduit.ban_manager;

    if (ban_mgr.entries.items.len == 0) {
        ctx.sendOutput(true, "No banned players");
        return;
    }

    var buf: [512]u8 = undefined;
    var pos: usize = 0;
    const header = "Banned players: ";
    @memcpy(buf[pos .. pos + header.len], header);
    pos += header.len;

    for (ban_mgr.entries.items, 0..) |entry, i| {
        if (i > 0) {
            if (pos + 2 < buf.len) {
                buf[pos] = ',';
                buf[pos + 1] = ' ';
                pos += 2;
            }
        }
        if (pos + entry.name.len < buf.len) {
            @memcpy(buf[pos .. pos + entry.name.len], entry.name);
            pos += entry.name.len;
        }
    }
    ctx.sendOutput(true, buf[0..pos]);
}
