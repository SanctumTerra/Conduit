const std = @import("std");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const Conduit = @import("../../conduit.zig").Conduit;

pub fn register(registry: *CommandRegistry, conduit: *Conduit) !void {
    const world_enum_idx = try registerWorldEnum(registry, conduit);
    const dim_enum_idx = try registry.registerEnum(.{
        .name = "DimensionName",
        .values = &.{ "overworld", "nether", "end" },
    });

    const cmd = try Command.init(
        registry.allocator,
        "world",
        "Transfer to a different world",
        "conduit.command.world",
        &.{},
        @ptrCast(&handle),
    );

    try cmd.addOverload(&.{
        .{ .name = "worldName", .param_type = .String, .optional = false, .enum_index = world_enum_idx },
    });
    try cmd.addOverload(&.{
        .{ .name = "worldName", .param_type = .String, .optional = false, .enum_index = world_enum_idx },
        .{ .name = "dimension", .param_type = .String, .optional = false, .enum_index = dim_enum_idx },
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
        .name = "TransferWorld",
        .values = values,
        .owned = true,
    });
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");

    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /world <name> [dimension]");
        return;
    }

    var iter = std.mem.splitScalar(u8, trimmed, ' ');
    const world_name = iter.next() orelse return;
    const dim_name = iter.next() orelse "overworld";

    const world = ctx.network.conduit.getWorld(world_name) orelse {
        ctx.sendOutput(false, "World not found");
        return;
    };

    const dimension = world.getDimension(dim_name) orelse {
        ctx.sendOutput(false, "Dimension not found in that world");
        return;
    };

    if (ctx.player.entity.dimension == dimension) {
        ctx.sendOutput(false, "Already in that world/dimension");
        return;
    }

    ctx.player.transferToDimension(dimension);
    ctx.sendOutput(true, "Transferring...");
}
