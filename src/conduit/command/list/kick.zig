const std = @import("std");
const Raknet = @import("Raknet");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");

pub fn register(registry: *CommandRegistry) !void {
    const cmd = try Command.init(
        registry.allocator,
        "kick",
        "Kick a player from the server",
        "conduit.command.kick",
        &.{},
        @ptrCast(&handle),
    );
    try cmd.addOverload(&.{
        .{ .name = "player", .param_type = .Target, .optional = false },
        .{ .name = "reason", .param_type = .Message, .optional = true },
    });
    try registry.registerCommand(cmd);
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /kick <player> [reason]");
        return;
    }

    const space_idx = std.mem.indexOfScalar(u8, trimmed, ' ');
    const target_name = if (space_idx) |idx| trimmed[0..idx] else trimmed;
    const reason = if (space_idx) |idx| std.mem.trim(u8, trimmed[idx + 1 ..], " ") else "Kicked by an operator.";

    const targets = ctx.resolvePlayers(target_name) orelse {
        ctx.sendOutput(false, "Player not found");
        return;
    };

    for (targets) |player| {
        Raknet.Logger.INFO("{s} kicked {s}: {s}", .{ ctx.player.username, player.username, reason });
        player.disconnect(reason) catch {};
    }

    var buf: [128]u8 = undefined;
    if (targets.len == 1) {
        const msg = std.fmt.bufPrint(&buf, "Kicked {s}", .{targets[0].username}) catch return;
        ctx.sendOutput(true, msg);
    } else {
        const msg = std.fmt.bufPrint(&buf, "Kicked {d} players", .{targets.len}) catch return;
        ctx.sendOutput(true, msg);
    }
}
