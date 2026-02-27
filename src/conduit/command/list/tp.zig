const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");

pub fn register(registry: *CommandRegistry) !void {
    const cmd = try Command.init(
        registry.allocator,
        "tp",
        "Teleport to a player or coordinates",
        "conduit.command.tp",
        &.{"teleport"},
        @ptrCast(&handle),
    );
    try cmd.addOverload(&.{
        .{ .name = "destination", .param_type = .Target, .optional = false },
    });
    try cmd.addOverload(&.{
        .{ .name = "x", .param_type = .Float, .optional = false },
        .{ .name = "y", .param_type = .Float, .optional = false },
        .{ .name = "z", .param_type = .Float, .optional = false },
    });
    try cmd.addOverload(&.{
        .{ .name = "victim", .param_type = .Target, .optional = false },
        .{ .name = "destination", .param_type = .Target, .optional = false },
    });
    try cmd.addOverload(&.{
        .{ .name = "victim", .param_type = .Target, .optional = false },
        .{ .name = "x", .param_type = .Float, .optional = false },
        .{ .name = "y", .param_type = .Float, .optional = false },
        .{ .name = "z", .param_type = .Float, .optional = false },
    });
    try registry.registerCommand(cmd);
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /tp <player> | /tp <x> <y> <z>");
        return;
    }

    var arg_iter = std.mem.splitScalar(u8, trimmed, ' ');
    const first = arg_iter.next() orelse return;

    const second = arg_iter.next();
    if (second == null) {
        const target = ctx.resolvePlayer(first) orelse {
            ctx.sendOutput(false, "Player not found");
            return;
        };
        teleportPlayer(ctx, ctx.player, target.entity.position);
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Teleported to {s}", .{target.username}) catch return;
        ctx.sendOutput(true, msg);
        return;
    }

    const third = arg_iter.next();
    if (third == null) {
        const victims = ctx.resolvePlayers(first) orelse {
            ctx.sendOutput(false, "Player not found");
            return;
        };
        const dest = ctx.resolvePlayer(second.?) orelse {
            ctx.sendOutput(false, "Destination player not found");
            return;
        };
        for (victims) |v| teleportPlayer(ctx, v, dest.entity.position);
        var buf: [128]u8 = undefined;
        if (victims.len == 1) {
            const msg = std.fmt.bufPrint(&buf, "Teleported {s} to {s}", .{ victims[0].username, dest.username }) catch return;
            ctx.sendOutput(true, msg);
        } else {
            const msg = std.fmt.bufPrint(&buf, "Teleported {d} players to {s}", .{ victims.len, dest.username }) catch return;
            ctx.sendOutput(true, msg);
        }
        return;
    }

    const pos = ctx.player.entity.position;
    const fourth = arg_iter.next();
    if (fourth == null) {
        const x = CommandContext.parseCoord(first, pos.x) orelse {
            ctx.sendOutput(false, "Invalid x coordinate");
            return;
        };
        const y = CommandContext.parseCoord(second.?, pos.y) orelse {
            ctx.sendOutput(false, "Invalid y coordinate");
            return;
        };
        const z = CommandContext.parseCoord(third.?, pos.z) orelse {
            ctx.sendOutput(false, "Invalid z coordinate");
            return;
        };
        teleportPlayer(ctx, ctx.player, Protocol.Vector3f.init(x, y, z));
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Teleported to {d:.1}, {d:.1}, {d:.1}", .{ x, y, z }) catch return;
        ctx.sendOutput(true, msg);
        return;
    }

    const victims = ctx.resolvePlayers(first) orelse {
        ctx.sendOutput(false, "Player not found");
        return;
    };
    for (victims) |victim| {
        const vpos = victim.entity.position;
        const x = CommandContext.parseCoord(second.?, vpos.x) orelse continue;
        const y = CommandContext.parseCoord(third.?, vpos.y) orelse continue;
        const z = CommandContext.parseCoord(fourth.?, vpos.z) orelse continue;
        teleportPlayer(ctx, victim, Protocol.Vector3f.init(x, y, z));
    }
    var buf: [128]u8 = undefined;
    if (victims.len == 1) {
        const msg = std.fmt.bufPrint(&buf, "Teleported {s}", .{victims[0].username}) catch return;
        ctx.sendOutput(true, msg);
    } else {
        const msg = std.fmt.bufPrint(&buf, "Teleported {d} players", .{victims.len}) catch return;
        ctx.sendOutput(true, msg);
    }
}

fn teleportPlayer(ctx: *CommandContext, player: *@import("../../player/player.zig").Player, pos: Protocol.Vector3f) void {
    player.entity.position = pos;

    var stream = BinaryStream.init(ctx.allocator, null, null);
    defer stream.deinit();

    const packet = Protocol.MovePlayerPacket{
        .runtime_id = @bitCast(player.entity.runtime_id),
        .position = pos,
        .pitch = player.entity.rotation.x,
        .yaw = player.entity.rotation.y,
        .head_yaw = player.entity.rotation.y,
        .mode = .Teleport,
        .on_ground = false,
    };
    const serialized = packet.serialize(&stream) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};
}
