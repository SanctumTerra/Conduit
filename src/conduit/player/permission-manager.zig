const std = @import("std");
const Raknet = @import("Raknet");

pub const PermissionGroup = struct {
    name: []const u8,
    permissions: std.StringHashMap(void),
};

pub const PermissionManager = struct {
    allocator: std.mem.Allocator,
    groups: std.StringHashMap(*PermissionGroup),
    player_groups: std.StringHashMap([]const u8),
    default_group: []const u8,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8, default_group: []const u8) PermissionManager {
        var mgr = PermissionManager{
            .allocator = allocator,
            .groups = std.StringHashMap(*PermissionGroup).init(allocator),
            .player_groups = std.StringHashMap([]const u8).init(allocator),
            .default_group = default_group,
            .path = path,
        };
        mgr.load();
        if (mgr.groups.count() == 0) mgr.createDefaults();
        return mgr;
    }

    pub fn deinit(self: *PermissionManager) void {
        var git = self.groups.valueIterator();
        while (git.next()) |group| {
            var kit = group.*.permissions.keyIterator();
            while (kit.next()) |key| {
                self.allocator.free(key.*);
            }
            self.allocator.free(group.*.name);
            group.*.permissions.deinit();
            self.allocator.destroy(group.*);
        }
        self.groups.deinit();
        var pit = self.player_groups.iterator();
        while (pit.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.player_groups.deinit();
    }

    pub fn hasPermission(self: *const PermissionManager, player_name: []const u8, permission: []const u8) bool {
        if (permission.len == 0) return true;

        const group_name = self.player_groups.get(player_name) orelse self.default_group;
        const group = self.groups.get(group_name) orelse return false;

        if (group.permissions.contains("*")) return true;
        if (group.permissions.contains(permission)) return true;

        if (std.mem.lastIndexOfScalar(u8, permission, '.')) |dot| {
            var buf: [128]u8 = undefined;
            if (dot + 2 <= buf.len) {
                @memcpy(buf[0..dot], permission[0..dot]);
                buf[dot] = '.';
                buf[dot + 1] = '*';
                if (group.permissions.contains(buf[0 .. dot + 2])) return true;
            }
        }

        return false;
    }

    pub fn getPlayerGroup(self: *const PermissionManager, player_name: []const u8) []const u8 {
        return self.player_groups.get(player_name) orelse self.default_group;
    }

    pub fn setPlayerGroup(self: *PermissionManager, player_name: []const u8, group_name: []const u8) !void {
        if (!self.groups.contains(group_name)) return error.GroupNotFound;

        if (self.player_groups.get(player_name)) |old| {
            self.allocator.free(old);
            _ = self.player_groups.remove(player_name);
        }

        const key = try self.allocator.dupe(u8, player_name);
        const val = try self.allocator.dupe(u8, group_name);
        try self.player_groups.put(key, val);
        self.save();
    }

    fn createDefaults(self: *PermissionManager) void {
        self.createGroup("member", &.{
            "conduit.command.about",
        }) catch {};
        self.createGroup("operator", &.{
            "*",
        }) catch {};
        self.save();
    }

    fn createGroup(self: *PermissionManager, name: []const u8, perms: []const []const u8) !void {
        const group = try self.allocator.create(PermissionGroup);
        group.* = .{
            .name = try self.allocator.dupe(u8, name),
            .permissions = std.StringHashMap(void).init(self.allocator),
        };
        for (perms) |p| {
            try group.permissions.put(try self.allocator.dupe(u8, p), {});
        }
        try self.groups.put(group.name, group);
    }

    fn load(self: *PermissionManager) void {
        const file = std.fs.cwd().openFile(self.path, .{}) catch return;
        defer file.close();
        const data = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return;
        defer self.allocator.free(data);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch return;
        defer parsed.deinit();

        const root = switch (parsed.value) {
            .object => |o| o,
            else => return,
        };

        if (root.get("groups")) |groups_val| {
            const groups_obj = switch (groups_val) {
                .object => |o| o,
                else => return,
            };
            var git = groups_obj.iterator();
            while (git.next()) |entry| {
                const group = self.allocator.create(PermissionGroup) catch continue;
                group.* = .{
                    .name = self.allocator.dupe(u8, entry.key_ptr.*) catch continue,
                    .permissions = std.StringHashMap(void).init(self.allocator),
                };
                const perms_arr = switch (entry.value_ptr.*) {
                    .array => |a| a,
                    else => continue,
                };
                for (perms_arr.items) |perm_val| {
                    const perm_str = switch (perm_val) {
                        .string => |s| s,
                        else => continue,
                    };
                    const duped = self.allocator.dupe(u8, perm_str) catch continue;
                    group.permissions.put(duped, {}) catch continue;
                }
                self.groups.put(group.name, group) catch continue;
            }
        }

        if (root.get("players")) |players_val| {
            const players_obj = switch (players_val) {
                .object => |o| o,
                else => return,
            };
            var pit = players_obj.iterator();
            while (pit.next()) |entry| {
                const val_str = switch (entry.value_ptr.*) {
                    .string => |s| s,
                    else => continue,
                };
                const key = self.allocator.dupe(u8, entry.key_ptr.*) catch continue;
                const val = self.allocator.dupe(u8, val_str) catch continue;
                self.player_groups.put(key, val) catch continue;
            }
        }

        Raknet.Logger.INFO("Loaded {d} permission groups, {d} player assignments", .{ self.groups.count(), self.player_groups.count() });
    }

    fn save(self: *PermissionManager) void {
        const file = std.fs.cwd().createFile(self.path, .{}) catch return;
        defer file.close();

        file.writeAll("{\n  \"groups\": {\n") catch return;
        var gi: usize = 0;
        var git = self.groups.iterator();
        while (git.next()) |entry| {
            var buf: [128]u8 = undefined;
            const header = std.fmt.bufPrint(&buf, "    \"{s}\": [\n", .{entry.key_ptr.*}) catch continue;
            file.writeAll(header) catch continue;

            var pi: usize = 0;
            const perm_count = entry.value_ptr.*.permissions.count();
            var pit = entry.value_ptr.*.permissions.keyIterator();
            while (pit.next()) |perm| {
                var pbuf: [256]u8 = undefined;
                const comma: []const u8 = if (pi + 1 < perm_count) "," else "";
                const line = std.fmt.bufPrint(&pbuf, "      \"{s}\"{s}\n", .{ perm.*, comma }) catch continue;
                file.writeAll(line) catch continue;
                pi += 1;
            }

            gi += 1;
            if (gi < self.groups.count()) {
                file.writeAll("    ],\n") catch continue;
            } else {
                file.writeAll("    ]\n") catch continue;
            }
        }

        file.writeAll("  },\n  \"players\": {\n") catch return;
        var pli: usize = 0;
        var plit = self.player_groups.iterator();
        while (plit.next()) |entry| {
            var buf: [256]u8 = undefined;
            pli += 1;
            const comma: []const u8 = if (pli < self.player_groups.count()) "," else "";
            const line = std.fmt.bufPrint(&buf, "    \"{s}\": \"{s}\"{s}\n", .{ entry.key_ptr.*, entry.value_ptr.*, comma }) catch continue;
            file.writeAll(line) catch continue;
        }
        file.writeAll("  }\n}\n") catch return;
    }
};
