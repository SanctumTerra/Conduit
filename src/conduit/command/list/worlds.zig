const std = @import("std");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");
const Conduit = @import("../../conduit.zig").Conduit;

pub fn register(registry: *CommandRegistry, conduit: *Conduit) !void {
    const world_enum_idx = try registerWorldEnum(registry, conduit);

    const cmd = try Command.init(
        registry.allocator,
        "worlds",
        "List all registered worlds",
        "conduit.command.worlds",
        &.{},
        @ptrCast(&handle),
    );

    try cmd.addOverload(&.{
        .{ .name = "worldName", .param_type = .String, .optional = true, .enum_index = world_enum_idx },
    });

    try registry.registerCommand(cmd);
}

fn registerWorldEnum(registry: *CommandRegistry, conduit: *Conduit) !u32 {
    var names = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer if (names.capacity > 0) names.deinit(registry.allocator);

    var it = conduit.worlds.keyIterator();
    while (it.next()) |key| {
        try names.append(registry.allocator, key.*);
    }

    const values = try registry.allocator.alloc([]const u8, names.items.len);
    @memcpy(values, names.items);

    return try registry.registerEnum(.{
        .name = "WorldName",
        .values = values,
        .owned = true,
    });
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const conduit = ctx.network.conduit;
    const trimmed = std.mem.trim(u8, ctx.args, " ");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    if (trimmed.len == 0) {
        std.fmt.format(writer, "Worlds (§v{d}§r):", .{conduit.worlds.count()}) catch return;
        var it = conduit.worlds.valueIterator();
        while (it.next()) |world| {
            std.fmt.format(writer, "\n  §v{s}§r:", .{world.*.identifier}) catch return;
            var dim_it = world.*.dimensions.valueIterator();
            while (dim_it.next()) |dim| {
                std.fmt.format(writer, "\n    §b{s}§r (§7spawn: §a{d}§7,§a{d}§7,§a{d}§r)", .{
                    dim.*.identifier,
                    dim.*.spawn_position.x,
                    dim.*.spawn_position.y,
                    dim.*.spawn_position.z,
                }) catch return;
            }
        }
        ctx.sendOutput(true, fbs.getWritten());
        return;
    }

    const world = conduit.getWorld(trimmed) orelse {
        ctx.sendOutput(false, "World not found");
        return;
    };

    const avg_tick_ms = conduit.profiler.avgTickMs();
    const slow_pct = conduit.profiler.slowTickPct();
    const tps_color: []const u8 = if (conduit.current_tps >= 19.5) "§a" else if (conduit.current_tps >= 15.0) "§e" else "§c";
    const slow_color: []const u8 = if (conduit.profiler.slow_ticks == 0) "§a" else if (slow_pct < 5.0) "§e" else "§c";

    std.fmt.format(writer, "§6World: §f{s}\n§7TPS: {s}{d:.1} §7Tick: §f{d:.2}ms §7SlowTicks: {s}{d} §7({d:.1}%%)", .{
        world.identifier,
        tps_color,
        conduit.current_tps,
        avg_tick_ms,
        slow_color,
        conduit.profiler.slow_ticks,
        slow_pct,
    }) catch return;

    const snapshots = conduit.getPlayerSnapshots();
    var dim_it = world.dimensions.valueIterator();
    while (dim_it.next()) |dim| {
        var player_count: usize = 0;
        for (snapshots) |player| {
            if (player.entity.dimension == dim.*) player_count += 1;
        }
        std.fmt.format(writer, "\n §b{s} §8[§7{s}§8]\n  §8Spawn: §f{d},{d},{d} §8SimDist: §f{d}\n  §8Chunks: §f{d} §8Entities: §f{d} §8Players: §f{d}", .{
            dim.*.identifier,
            @tagName(dim.*.dimension_type),
            dim.*.spawn_position.x,
            dim.*.spawn_position.y,
            dim.*.spawn_position.z,
            dim.*.simulation_distance,
            dim.*.chunks.count(),
            dim.*.entities.count(),
            player_count,
        }) catch return;
    }
    ctx.sendOutput(true, fbs.getWritten());
}
