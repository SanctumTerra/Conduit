const std = @import("std");
const Protocol = @import("protocol");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;
const types = @import("../types.zig");
const EntityTypeRegistry = @import("../../entity/entity-type-registry.zig");

pub fn register(registry: *CommandRegistry) !void {
    const entity_enum_idx = try registerEntityEnum(registry);

    const cmd = try Command.init(
        registry.allocator,
        "summon",
        "Summon an entity",
        "conduit.command.summon",
        &.{},
        @ptrCast(&handle),
    );

    const params = try registry.allocator.alloc(types.CommandParameter, 3);
    params[0] = .{
        .name = "entityType",
        .param_type = .String,
        .optional = false,
        .enum_index = entity_enum_idx,
    };
    params[1] = .{
        .name = "nameTag",
        .param_type = .String,
        .optional = true,
    };
    params[2] = .{
        .name = "alwaysVisible",
        .param_type = .String,
        .optional = true,
    };
    try cmd.addOverload(params);
    registry.allocator.free(params);
    try registry.registerCommand(cmd);
}

fn registerEntityEnum(registry: *CommandRegistry) !u32 {
    const reg = EntityTypeRegistry.EntityTypeRegistry.getRegistry() orelse return error.NoEntityRegistry;
    var names = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer if (names.capacity > 0) names.deinit(registry.allocator);

    var it = reg.types.keyIterator();
    while (it.next()) |key| {
        const id = key.*;
        if (std.mem.eql(u8, id, "minecraft:player")) continue;
        const short = if (std.mem.startsWith(u8, id, "minecraft:")) id[10..] else id;
        try names.append(registry.allocator, short);
    }

    const values = try registry.allocator.alloc([]const u8, names.items.len);
    @memcpy(values, names.items);

    return try registry.registerEnum(.{
        .name = "EntityType",
        .values = values,
        .owned = true,
    });
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    const trimmed = std.mem.trim(u8, ctx.args, " ");
    if (trimmed.len == 0) {
        ctx.sendOutput(false, "Usage: /summon <entityType> [nameTag] [alwaysVisible]");
        return;
    }

    var arg_iter = std.mem.splitScalar(u8, trimmed, ' ');
    const entity_name = arg_iter.next() orelse {
        ctx.sendOutput(false, "Usage: /summon <entityType> [nameTag] [alwaysVisible]");
        return;
    };
    const name_tag = arg_iter.next();
    const always_visible = if (arg_iter.next()) |v|
        std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "1")
    else
        false;

    var identifier_buf: [128]u8 = undefined;
    const identifier = if (std.mem.indexOf(u8, entity_name, ":") != null)
        entity_name
    else blk: {
        const written = std.fmt.bufPrint(&identifier_buf, "minecraft:{s}", .{entity_name}) catch {
            ctx.sendOutput(false, "Entity name too long");
            return;
        };
        break :blk written;
    };

    const entity_type = EntityTypeRegistry.EntityTypeRegistry.get(identifier) orelse {
        ctx.sendOutput(false, "Unknown entity type");
        return;
    };

    const world = ctx.network.conduit.getWorld("world") orelse return;
    const dimension = world.getDimension("overworld") orelse return;

    const pos = ctx.player.entity.position;
    const spawn_pos = Protocol.Vector3f.init(pos.x, pos.y - 1.62, pos.z);

    if (name_tag) |tag| {
        _ = dimension.spawnEntityWithOptions(entity_type, spawn_pos, tag, always_visible) catch {
            ctx.sendOutput(false, "Failed to summon entity");
            return;
        };
    } else {
        _ = dimension.spawnEntity(entity_type, spawn_pos) catch {
            ctx.sendOutput(false, "Failed to summon entity");
            return;
        };
    }

    var msg_buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Summoned {s}", .{entity_name}) catch return;
    ctx.sendOutput(true, msg);
}
