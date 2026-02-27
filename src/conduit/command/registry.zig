const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Raknet = @import("Raknet");
const Command = @import("command.zig").Command;
const CommandHandlerFn = @import("command.zig").CommandHandlerFn;
const CommandContext = @import("context.zig").CommandContext;
const CommandPermission = @import("permission.zig").CommandPermission;
const types = @import("types.zig");
const CommandEnum = types.CommandEnum;
const SoftEnum = types.SoftEnum;
const CommandParameter = types.CommandParameter;
const CommandOverload = types.CommandOverload;
const Player = @import("../player/player.zig").Player;
const NetworkHandler = @import("../network/network-handler.zig").NetworkHandler;

pub const CommandResult = struct {
    success: bool,
    message: []const u8,
};

fn permissionToString(perm: CommandPermission) []const u8 {
    _ = perm;
    return "any";
}

pub const CommandRegistry = struct {
    allocator: std.mem.Allocator,
    commands: std.StringHashMap(*Command),
    alias_map: std.StringHashMap(*Command),
    enums: std.ArrayList(CommandEnum),
    soft_enums: std.ArrayList(SoftEnum),

    pub fn init(allocator: std.mem.Allocator) CommandRegistry {
        return .{
            .allocator = allocator,
            .commands = std.StringHashMap(*Command).init(allocator),
            .alias_map = std.StringHashMap(*Command).init(allocator),
            .enums = std.ArrayList(CommandEnum){ .items = &.{}, .capacity = 0 },
            .soft_enums = std.ArrayList(SoftEnum){ .items = &.{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *CommandRegistry) void {
        var it = self.commands.valueIterator();
        while (it.next()) |cmd| {
            cmd.*.deinit();
        }
        self.commands.deinit();
        self.alias_map.deinit();
        for (self.enums.items) |e| {
            self.allocator.free(e.values);
        }
        if (self.enums.capacity > 0) self.enums.deinit(self.allocator);
        if (self.soft_enums.capacity > 0) self.soft_enums.deinit(self.allocator);
    }

    pub fn registerCommand(self: *CommandRegistry, cmd: *Command) !void {
        try self.commands.put(cmd.name, cmd);
        for (cmd.aliases) |alias| {
            try self.alias_map.put(alias, cmd);
        }
    }

    pub fn registerEnum(self: *CommandRegistry, enum_def: CommandEnum) !u32 {
        const idx: u32 = @intCast(self.enums.items.len);
        try self.enums.append(self.allocator, enum_def);
        return idx;
    }

    pub fn registerSoftEnum(self: *CommandRegistry, soft_enum: SoftEnum) !u32 {
        const idx: u32 = @intCast(self.soft_enums.items.len);
        try self.soft_enums.append(self.allocator, soft_enum);
        return idx;
    }

    pub fn findCommand(self: *CommandRegistry, name: []const u8) ?*Command {
        return self.commands.get(name) orelse self.alias_map.get(name);
    }

    pub fn parseCommandName(command_line: []const u8) ?struct { name: []const u8, args: []const u8 } {
        if (command_line.len == 0) return null;

        var line = command_line;
        if (line[0] == '/') {
            line = line[1..];
        }
        if (line.len == 0) return null;

        if (std.mem.indexOfScalar(u8, line, ' ')) |space_idx| {
            return .{
                .name = line[0..space_idx],
                .args = line[space_idx + 1 ..],
            };
        }
        return .{ .name = line, .args = "" };
    }

    pub fn dispatch(
        self: *CommandRegistry,
        player: *Player,
        network: *NetworkHandler,
        command_line: []const u8,
        origin_type: []const u8,
        uuid: [16]u8,
        request_id: []const u8,
    ) CommandResult {
        const parsed = parseCommandName(command_line) orelse {
            return .{ .success = false, .message = "Invalid command" };
        };

        const cmd = self.findCommand(parsed.name) orelse {
            return .{ .success = false, .message = "Unknown command" };
        };

        const conduit = network.conduit;
        if (cmd.permission.len > 0 and !conduit.permission_manager.hasPermission(player.username, cmd.permission)) {
            return .{ .success = false, .message = "You do not have permission to run this command" };
        }

        var ctx = CommandContext{
            .player = player,
            .args = parsed.args,
            .network = network,
            .allocator = self.allocator,
            .origin_type = origin_type,
            .uuid = uuid,
            .request_id = request_id,
        };

        if (cmd.subcommands.count() > 0 and parsed.args.len > 0) {
            const first_arg_end = std.mem.indexOfScalar(u8, parsed.args, ' ') orelse parsed.args.len;
            const first_arg = parsed.args[0..first_arg_end];
            if (cmd.subcommands.get(first_arg)) |sub| {
                ctx.args = if (first_arg_end < parsed.args.len) parsed.args[first_arg_end + 1 ..] else "";
                sub.handler(@ptrCast(&ctx));
                return .{ .success = true, .message = "" };
            }
        }

        cmd.handler(@ptrCast(&ctx));
        return .{ .success = true, .message = "" };
    }

    pub fn buildAvailableCommandsPacket(self: *CommandRegistry, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Protocol.Packet.AvailableCommands);

        var enum_value_list = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        defer enum_value_list.deinit(self.allocator);
        var enum_value_map = std.StringHashMap(u32).init(self.allocator);
        defer enum_value_map.deinit();

        const PacketEnum = struct {
            name: []const u8,
            indices: std.ArrayList(u32),
        };

        var packet_enums = std.ArrayList(PacketEnum){ .items = &.{}, .capacity = 0 };
        defer {
            for (packet_enums.items) |*pe| pe.indices.deinit(self.allocator);
            packet_enums.deinit(self.allocator);
        }

        for (self.enums.items) |cmd_enum| {
            var pe = PacketEnum{
                .name = cmd_enum.name,
                .indices = std.ArrayList(u32){ .items = &.{}, .capacity = 0 },
            };
            for (cmd_enum.values) |val| {
                if (!enum_value_map.contains(val)) {
                    const idx: u32 = @intCast(enum_value_list.items.len);
                    try enum_value_list.append(self.allocator, val);
                    try enum_value_map.put(val, idx);
                }
                try pe.indices.append(self.allocator, enum_value_map.get(val).?);
            }
            try packet_enums.append(self.allocator, pe);
        }

        var subcommand_enum_indices = std.StringHashMap(u32).init(self.allocator);
        defer subcommand_enum_indices.deinit();

        var cmd_it_sub = self.commands.valueIterator();
        while (cmd_it_sub.next()) |cmd| {
            if (cmd.*.subcommand_enum) |sc_enum| {
                var pe = PacketEnum{
                    .name = sc_enum.name,
                    .indices = std.ArrayList(u32){ .items = &.{}, .capacity = 0 },
                };
                for (sc_enum.values) |val| {
                    if (!enum_value_map.contains(val)) {
                        const idx: u32 = @intCast(enum_value_list.items.len);
                        try enum_value_list.append(self.allocator, val);
                        try enum_value_map.put(val, idx);
                    }
                    try pe.indices.append(self.allocator, enum_value_map.get(val).?);
                }
                const enum_idx: u32 = @intCast(packet_enums.items.len);
                try packet_enums.append(self.allocator, pe);
                try subcommand_enum_indices.put(cmd.*.name, enum_idx);
            }
        }

        const AliasEntry = struct { cmd_name: []const u8, enum_idx: u32 };
        var alias_enums = std.ArrayList(AliasEntry){ .items = &.{}, .capacity = 0 };
        defer alias_enums.deinit(self.allocator);

        var alias_names = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        defer {
            for (alias_names.items) |n| self.allocator.free(n);
            alias_names.deinit(self.allocator);
        }

        var cmd_it = self.commands.valueIterator();
        while (cmd_it.next()) |cmd| {
            if (cmd.*.aliases.len > 0) {
                const alloc_name = std.fmt.allocPrint(self.allocator, "{s}Aliases", .{cmd.*.name}) catch cmd.*.name;
                var pe = PacketEnum{
                    .name = alloc_name,
                    .indices = std.ArrayList(u32){ .items = &.{}, .capacity = 0 },
                };
                if (alloc_name.ptr != cmd.*.name.ptr) {
                    try alias_names.append(self.allocator, alloc_name);
                }
                for (cmd.*.aliases) |alias| {
                    if (!enum_value_map.contains(alias)) {
                        const idx: u32 = @intCast(enum_value_list.items.len);
                        try enum_value_list.append(self.allocator, alias);
                        try enum_value_map.put(alias, idx);
                    }
                    try pe.indices.append(self.allocator, enum_value_map.get(alias).?);
                }
                const enum_idx: u32 = @intCast(packet_enums.items.len);
                try packet_enums.append(self.allocator, pe);
                try alias_enums.append(self.allocator, .{ .cmd_name = cmd.*.name, .enum_idx = enum_idx });
            }
        }

        try stream.writeVarInt(@intCast(enum_value_list.items.len));
        for (enum_value_list.items) |val| {
            try stream.writeVarString(val);
        }

        try stream.writeVarInt(0);

        try stream.writeVarInt(0);

        try stream.writeVarInt(@intCast(packet_enums.items.len));
        for (packet_enums.items) |pe| {
            try stream.writeVarString(pe.name);
            try stream.writeVarInt(@intCast(pe.indices.items.len));
            for (pe.indices.items) |idx| {
                try stream.writeUint32(idx, .Little);
            }
        }

        try stream.writeVarInt(0);

        try stream.writeVarInt(@intCast(self.commands.count()));
        var cmd_it2 = self.commands.valueIterator();
        while (cmd_it2.next()) |cmd| {
            try stream.writeVarString(cmd.*.name);
            try stream.writeVarString(cmd.*.description);
            try stream.writeUint16(0, .Little);
            try stream.writeVarString(permissionToString(cmd.*.permission));

            var aliases_offset: u32 = 0xFFFFFFFF;
            for (alias_enums.items) |ae| {
                if (std.mem.eql(u8, ae.cmd_name, cmd.*.name)) {
                    aliases_offset = ae.enum_idx;
                    break;
                }
            }
            try stream.writeUint32(aliases_offset, .Little);

            try stream.writeVarInt(0);

            try stream.writeVarInt(@intCast(cmd.*.overloads.items.len));
            for (cmd.*.overloads.items) |overload| {
                try stream.writeBool(overload.chaining);
                try stream.writeVarInt(@intCast(overload.params.len));
                for (overload.params) |param| {
                    var type_field = param.computeTypeField();
                    if (param.enum_index == null and param.soft_enum_index == null) {
                        if (cmd.*.subcommand_enum) |sc_enum| {
                            if (std.mem.eql(u8, param.name, sc_enum.name)) {
                                if (subcommand_enum_indices.get(cmd.*.name)) |sc_idx| {
                                    type_field = types.CommandArgValid | types.CommandArgEnum | sc_idx;
                                }
                            }
                        }
                    }
                    try stream.writeVarString(param.name);
                    try stream.writeUint32(type_field, .Little);
                    try stream.writeBool(param.optional);
                    try stream.writeUint8(param.options);
                }
            }
        }

        try stream.writeVarInt(@intCast(self.soft_enums.items.len));
        for (self.soft_enums.items) |se| {
            try stream.writeVarString(se.name);
            try stream.writeVarInt(@intCast(se.values.len));
            for (se.values) |val| {
                try stream.writeVarString(val);
            }
        }

        try stream.writeVarInt(0);

        return stream.getBuffer();
    }
};
