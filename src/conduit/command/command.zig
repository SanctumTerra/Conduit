const std = @import("std");
const CommandPermission = @import("permission.zig").CommandPermission;
const types = @import("types.zig");
const CommandParameter = types.CommandParameter;
const CommandOverload = types.CommandOverload;
const CommandEnum = types.CommandEnum;

pub const CommandHandlerFn = *const fn (ctx: *anyopaque) void;

pub const SubCommand = struct {
    name: []const u8,
    aliases: []const []const u8,
    params: []const CommandParameter,
    handler: CommandHandlerFn,
};

pub const Command = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    permission: CommandPermission,
    aliases: []const []const u8,
    overloads: std.ArrayList(CommandOverload),
    subcommands: std.StringHashMap(*SubCommand),
    handler: CommandHandlerFn,
    subcommand_enum: ?CommandEnum = null,
    subcommand_overload_params: std.ArrayList([]const CommandParameter),

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        description: []const u8,
        permission: CommandPermission,
        aliases: []const []const u8,
        handler: CommandHandlerFn,
    ) !*Command {
        const cmd = try allocator.create(Command);
        cmd.* = .{
            .allocator = allocator,
            .name = name,
            .description = description,
            .permission = permission,
            .aliases = aliases,
            .overloads = std.ArrayList(CommandOverload){ .items = &.{}, .capacity = 0 },
            .subcommands = std.StringHashMap(*SubCommand).init(allocator),
            .handler = handler,
            .subcommand_enum = null,
            .subcommand_overload_params = std.ArrayList([]const CommandParameter){ .items = &.{}, .capacity = 0 },
        };
        return cmd;
    }

    pub fn deinit(self: *Command) void {
        for (self.overloads.items) |overload| {
            if (!self.isSubcommandOverload(overload)) {
                self.allocator.free(overload.params);
            }
        }
        if (self.overloads.capacity > 0) self.overloads.deinit(self.allocator);
        for (self.subcommand_overload_params.items) |params| {
            self.allocator.free(params);
        }
        if (self.subcommand_overload_params.capacity > 0) self.subcommand_overload_params.deinit(self.allocator);
        if (self.subcommand_enum) |se| {
            self.allocator.free(se.name);
            self.allocator.free(se.values);
        }
        var sub_seen = std.StringHashMap(void).init(self.allocator);
        defer sub_seen.deinit();
        var sub_it = self.subcommands.iterator();
        while (sub_it.next()) |entry| {
            const sub = entry.value_ptr.*;
            if (!sub_seen.contains(sub.name)) {
                sub_seen.put(sub.name, {}) catch {};
                self.allocator.destroy(sub);
            }
        }
        self.subcommands.deinit();
        self.allocator.destroy(self);
    }

    pub fn addOverload(self: *Command, params: []const CommandParameter) !void {
        const duped = try self.allocator.dupe(CommandParameter, params);
        try self.overloads.append(self.allocator, .{ .params = duped });
    }

    pub fn registerSubCommand(self: *Command, sub: *SubCommand) !void {
        try self.subcommands.put(sub.name, sub);
        for (sub.aliases) |alias| {
            try self.subcommands.put(alias, sub);
        }
        try self.rebuildSubcommandOverloads();
    }

    fn rebuildSubcommandOverloads(self: *Command) !void {
        var i: usize = self.overloads.items.len;
        while (i > 0) {
            i -= 1;
            if (self.isSubcommandOverload(self.overloads.items[i])) {
                _ = self.overloads.orderedRemove(i);
            }
        }
        for (self.subcommand_overload_params.items) |params| {
            self.allocator.free(params);
        }
        self.subcommand_overload_params.clearRetainingCapacity();
        if (self.subcommand_enum) |se| {
            self.allocator.free(se.name);
            self.allocator.free(se.values);
            self.subcommand_enum = null;
        }
        var unique_names = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        defer unique_names.deinit(self.allocator);
        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();
        var it = self.subcommands.iterator();
        while (it.next()) |entry| {
            const sub = entry.value_ptr.*;
            if (!seen.contains(sub.name)) {
                try seen.put(sub.name, {});
                try unique_names.append(self.allocator, sub.name);
            }
        }
        if (unique_names.items.len == 0) return;
        const enum_values = try self.allocator.alloc([]const u8, unique_names.items.len);
        @memcpy(enum_values, unique_names.items);
        self.subcommand_enum = .{
            .name = try std.fmt.allocPrint(self.allocator, "{s}SubCommands", .{self.name}),
            .values = enum_values,
        };
        var added = std.StringHashMap(void).init(self.allocator);
        defer added.deinit();
        var sub_it = self.subcommands.iterator();
        while (sub_it.next()) |entry| {
            const sub = entry.value_ptr.*;
            if (added.contains(sub.name)) continue;
            try added.put(sub.name, {});
            const params = try self.allocator.alloc(CommandParameter, 1 + sub.params.len);
            params[0] = .{
                .name = self.subcommand_enum.?.name,
                .param_type = .Int,
                .optional = false,
                .options = 0,
                .enum_index = null,
                .soft_enum_index = null,
            };
            @memcpy(params[1..], sub.params);
            try self.subcommand_overload_params.append(self.allocator, params);
            try self.overloads.append(self.allocator, .{ .params = params });
        }
    }

    fn isSubcommandOverload(self: *Command, overload: CommandOverload) bool {
        for (self.subcommand_overload_params.items) |params| {
            if (params.ptr == overload.params.ptr) return true;
        }
        return false;
    }
};
