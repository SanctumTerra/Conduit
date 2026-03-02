const std = @import("std");
const Raknet = @import("Raknet");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;

pub fn register(registry: *CommandRegistry) !void {
    const op_cmd = try Command.init(
        registry.allocator,
        "op",
        "Grant operator permissions to a player",
        "conduit.command.op",
        &.{},
        @ptrCast(&handleOp),
    );
    try op_cmd.addOverload(&.{
        .{ .name = "player", .param_type = .String, .optional = false },
    });
    try registry.registerCommand(op_cmd);

    const deop_cmd = try Command.init(
        registry.allocator,
        "deop",
        "Revoke operator permissions from a player",
        "conduit.command.op",
        &.{},
        @ptrCast(&handleDeop),
    );
    try deop_cmd.addOverload(&.{
        .{ .name = "player", .param_type = .String, .optional = false },
    });
    try registry.registerCommand(deop_cmd);
}

fn handleOp(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const name = std.mem.trim(u8, ctx.args, " ");
    if (name.len == 0) {
        ctx.sendOutput(false, "Usage: /op <player>");
        return;
    }

    const perm_mgr = &ctx.network.conduit.permission_manager;

    if (std.mem.eql(u8, perm_mgr.getPlayerGroup(name), "operator")) {
        ctx.sendOutput(false, "Player is already an operator");
        return;
    }

    perm_mgr.setPlayerGroup(name, "operator") catch {
        ctx.sendOutput(false, "Failed to grant operator (is the 'operator' group defined?)");
        return;
    };

    Raknet.Logger.INFO("{s} opped {s}", .{ ctx.player.username, name });

    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Granted operator to {s}", .{name}) catch return;
    ctx.sendOutput(true, msg);
}

fn handleDeop(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const name = std.mem.trim(u8, ctx.args, " ");
    if (name.len == 0) {
        ctx.sendOutput(false, "Usage: /deop <player>");
        return;
    }

    const perm_mgr = &ctx.network.conduit.permission_manager;

    if (!std.mem.eql(u8, perm_mgr.getPlayerGroup(name), "operator")) {
        ctx.sendOutput(false, "Player is not an operator");
        return;
    }

    perm_mgr.setPlayerGroup(name, perm_mgr.default_group) catch {
        ctx.sendOutput(false, "Failed to revoke operator");
        return;
    };

    Raknet.Logger.INFO("{s} deopped {s}", .{ ctx.player.username, name });

    var buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Revoked operator from {s}", .{name}) catch return;
    ctx.sendOutput(true, msg);
}
