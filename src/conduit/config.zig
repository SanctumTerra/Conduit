const std = @import("std");
const Raknet = @import("Raknet");

pub const ServerProperties = struct {
    address: []const u8 = "127.0.0.1",
    port: u16 = 19132,
    motd: []const u8 = "Conduit Server",
    max_players: u32 = 120,
    online_mode: bool = true,
    max_tps: u32 = 20,
    max_view_distance: u32 = 16,
    simulation_distance: u32 = 4,
    default_group: []const u8 = "operator",

    allocator: std.mem.Allocator,
    _allocated_strings: std.ArrayListUnmanaged([]const u8) = .{},

    const comments = .{
        .address = "What address should the server run on",
        .port = "What port should the server run on",
        .motd = "What motd should server display in the server list",
        .max_players = "Max Player count on the server",
        .online_mode = "Whether to use online mode (WIP)",
        .max_tps = "Max tps",
        .max_view_distance = "Max view distance in chunks",
        .simulation_distance = "Simulation distance in chunks (chunks within this range are kept loaded)",
        .default_group = "Default permission group for new players",
    };

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !ServerProperties {
        var self = ServerProperties{ .allocator = allocator };

        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                Raknet.Logger.INFO("server.properties not found, creating with defaults", .{});
                try self.save(path);
                return self;
            },
            else => return err,
        };
        defer file.close();

        Raknet.Logger.INFO("Loading server.properties", .{});
        const content = try file.readToEndAlloc(allocator, 1024 * 64);
        defer allocator.free(content);

        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |raw_line| {
            const line = std.mem.trimRight(u8, raw_line, "\r");
            if (line.len == 0 or line[0] == '#') continue;

            const sep = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = line[0..sep];
            const value = line[sep + 1 ..];

            self.setField(key, value) catch |err| {
                Raknet.Logger.WARN("Unknown or invalid property: {s} ({any})", .{ key, err });
            };
        }

        return self;
    }

    fn setField(self: *ServerProperties, key: []const u8, value: []const u8) !void {
        inline for (@typeInfo(ServerProperties).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "allocator") or
                std.mem.eql(u8, field.name, "_allocated_strings")) continue;

            const file_key = comptime blk: {
                var name_buf: [field.name.len]u8 = undefined;
                @memcpy(&name_buf, field.name);
                std.mem.replaceScalar(u8, &name_buf, '_', '-');
                break :blk name_buf;
            };

            if (std.mem.eql(u8, key, &file_key)) {
                if (field.type == []const u8) {
                    const duped = try self.allocator.dupe(u8, value);
                    try self._allocated_strings.append(self.allocator, duped);
                    @field(self, field.name) = duped;
                } else if (field.type == bool) {
                    @field(self, field.name) = std.mem.eql(u8, value, "true");
                } else if (@typeInfo(field.type) == .int) {
                    @field(self, field.name) = std.fmt.parseInt(field.type, value, 10) catch return error.InvalidValue;
                }
                return;
            }
        }
        return error.UnknownProperty;
    }

    pub fn save(self: *const ServerProperties, path: []const u8) !void {
        var buf: [4096]u8 = undefined;
        var pos: usize = 0;

        inline for (@typeInfo(ServerProperties).@"struct".fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "allocator") or
                std.mem.eql(u8, field.name, "_allocated_strings")) continue;

            const file_key = comptime blk: {
                var name_buf: [field.name.len]u8 = undefined;
                @memcpy(&name_buf, field.name);
                std.mem.replaceScalar(u8, &name_buf, '_', '-');
                break :blk name_buf;
            };

            if (@hasField(@TypeOf(comments), field.name)) {
                const comment = std.fmt.bufPrint(buf[pos..], "# {s}\n", .{@field(comments, field.name)}) catch return error.BufferOverflow;
                pos += comment.len;
            }

            const val = @field(self, field.name);
            const line = if (field.type == []const u8)
                std.fmt.bufPrint(buf[pos..], "{s}={s}\n", .{ file_key, val }) catch return error.BufferOverflow
            else if (field.type == bool)
                std.fmt.bufPrint(buf[pos..], "{s}={s}\n", .{ file_key, if (val) "true" else "false" }) catch return error.BufferOverflow
            else if (@typeInfo(field.type) == .int)
                std.fmt.bufPrint(buf[pos..], "{s}={d}\n", .{ file_key, val }) catch return error.BufferOverflow
            else
                unreachable;
            pos += line.len;
        }

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        file.writeAll(buf[0..pos]) catch return error.WriteError;
    }

    pub fn deinit(self: *ServerProperties) void {
        for (self._allocated_strings.items) |s| {
            self.allocator.free(s);
        }
        self._allocated_strings.deinit(self.allocator);
    }
};
