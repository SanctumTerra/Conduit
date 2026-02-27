const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");

pub fn register(registry: *CommandRegistry) !void {
    const enum_idx = try registry.registerEnum(.{
        .name = "GameMode",
        .values = &.{ "survival", "creative", "adventure", "spectator", "s", "c", "a", "sp", "0", "1", "2", "6" },
    });

    const cmd = try Command.init(
        registry.allocator,
        "gamemode",
        "Set a player's game mode",
        "conduit.command.gamemode",
        &.{},
        @ptrCast(&handle),
    );
    try cmd.addOverload(&.{
        .{ .name = "gameMode", .param_type = .Int, .optional = false, .enum_index = enum_idx },
    });
    try cmd.addOverload(&.{
        .{ .name = "gameMode", .param_type = .Int, .optional = false, .enum_index = enum_idx },
        .{ .name = "player", .param_type = .Target, .optional = true },
    });
    try registry.registerCommand(cmd);
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /gamemode <mode> [player]");
        return;
    }

    var arg_iter = std.mem.splitScalar(u8, trimmed, ' ');
    const mode_str = arg_iter.next() orelse return;
    const target_name = arg_iter.next();

    const targets = if (target_name) |name| ctx.resolvePlayers(name) orelse {
        ctx.sendOutput(false, "Player not found");
        return;
    } else blk: {
        const slice = ctx.allocator.alloc(*@import("../../player/player.zig").Player, 1) catch return;
        slice[0] = ctx.player;
        break :blk slice;
    };

    const gamemode = parseGamemode(mode_str) orelse {
        ctx.sendOutput(false, "Unknown game mode");
        return;
    };

    for (targets) |target| {
        target.gamemode = gamemode;

        var stream = BinaryStream.init(ctx.allocator, null, null);
        defer stream.deinit();
        const packet = Protocol.SetPlayerGameTypePacket{ .gamemode = @intFromEnum(gamemode) };
        const serialized = packet.serialize(&stream) catch continue;
        target.network.sendPacket(target.connection, serialized) catch {};
    }

    var buf: [64]u8 = undefined;
    const name = gamemodeName(gamemode);
    if (targets.len == 1) {
        const msg = std.fmt.bufPrint(&buf, "Set {s}'s game mode to {s}", .{ targets[0].username, name }) catch return;
        ctx.sendOutput(true, msg);
    } else {
        const msg = std.fmt.bufPrint(&buf, "Set {d} players' game mode to {s}", .{ targets.len, name }) catch return;
        ctx.sendOutput(true, msg);
    }
}

fn parseGamemode(str: []const u8) ?Protocol.GameMode {
    if (std.mem.eql(u8, str, "survival") or std.mem.eql(u8, str, "s") or std.mem.eql(u8, str, "0")) return .Survival;
    if (std.mem.eql(u8, str, "creative") or std.mem.eql(u8, str, "c") or std.mem.eql(u8, str, "1")) return .Creative;
    if (std.mem.eql(u8, str, "adventure") or std.mem.eql(u8, str, "a") or std.mem.eql(u8, str, "2")) return .Adventure;
    if (std.mem.eql(u8, str, "spectator") or std.mem.eql(u8, str, "sp") or std.mem.eql(u8, str, "6")) return .Spectator;
    return null;
}

fn gamemodeName(mode: Protocol.GameMode) []const u8 {
    return switch (mode) {
        .Survival => "Survival",
        .Creative => "Creative",
        .Adventure => "Adventure",
        .Spectator => "Spectator",
        else => "Unknown",
    };
}
