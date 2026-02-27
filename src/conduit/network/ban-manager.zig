const std = @import("std");
const Raknet = @import("Raknet");

pub const BanEntry = struct {
    uuid: []const u8,
    name: []const u8,
    created: []const u8,
    source: []const u8,
    expires: []const u8,
    reason: []const u8,
};

pub const BanManager = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(BanEntry),
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) BanManager {
        var mgr = BanManager{
            .allocator = allocator,
            .entries = std.ArrayList(BanEntry){ .items = &.{}, .capacity = 0 },
            .path = path,
        };
        mgr.load();
        return mgr;
    }

    pub fn deinit(self: *BanManager) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.uuid);
            self.allocator.free(entry.name);
            self.allocator.free(entry.created);
            self.allocator.free(entry.source);
            self.allocator.free(entry.expires);
            self.allocator.free(entry.reason);
        }
        if (self.entries.capacity > 0) self.entries.deinit(self.allocator);
    }

    pub fn isBanned(self: *const BanManager, name: []const u8) bool {
        for (self.entries.items) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return true;
        }
        return false;
    }

    pub fn isBannedByXuid(self: *const BanManager, uuid: []const u8) bool {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.uuid, uuid)) return true;
        }
        return false;
    }

    pub fn ban(self: *BanManager, uuid: []const u8, name: []const u8, source: []const u8, reason: []const u8) !void {
        if (self.isBanned(name)) return;

        const entry = BanEntry{
            .uuid = try self.allocator.dupe(u8, uuid),
            .name = try self.allocator.dupe(u8, name),
            .created = try self.allocator.dupe(u8, "unknown"),
            .source = try self.allocator.dupe(u8, source),
            .expires = try self.allocator.dupe(u8, "forever"),
            .reason = try self.allocator.dupe(u8, reason),
        };
        try self.entries.append(self.allocator, entry);
        self.save();
    }

    pub fn unban(self: *BanManager, name: []const u8) bool {
        for (self.entries.items, 0..) |entry, i| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) {
                self.allocator.free(entry.uuid);
                self.allocator.free(entry.name);
                self.allocator.free(entry.created);
                self.allocator.free(entry.source);
                self.allocator.free(entry.expires);
                self.allocator.free(entry.reason);
                _ = self.entries.orderedRemove(i);
                self.save();
                return true;
            }
        }
        return false;
    }

    fn load(self: *BanManager) void {
        const file = std.fs.cwd().openFile(self.path, .{}) catch return;
        defer file.close();
        const data = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return;
        defer self.allocator.free(data);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch return;
        defer parsed.deinit();

        const arr = switch (parsed.value) {
            .array => |a| a,
            else => return,
        };

        for (arr.items) |item| {
            const obj = switch (item) {
                .object => |o| o,
                else => continue,
            };
            const entry = BanEntry{
                .uuid = self.allocator.dupe(u8, getStr(obj, "uuid")) catch continue,
                .name = self.allocator.dupe(u8, getStr(obj, "name")) catch continue,
                .created = self.allocator.dupe(u8, getStr(obj, "created")) catch continue,
                .source = self.allocator.dupe(u8, getStr(obj, "source")) catch continue,
                .expires = self.allocator.dupe(u8, getStr(obj, "expires")) catch continue,
                .reason = self.allocator.dupe(u8, getStr(obj, "reason")) catch continue,
            };
            self.entries.append(self.allocator, entry) catch continue;
        }
        Raknet.Logger.INFO("Loaded {d} banned players", .{self.entries.items.len});
    }

    fn save(self: *BanManager) void {
        const file = std.fs.cwd().createFile(self.path, .{}) catch return;
        defer file.close();
        file.writeAll("[\n") catch return;
        for (self.entries.items, 0..) |entry, i| {
            file.writeAll("  {\n") catch return;
            writeField(file, "uuid", entry.uuid);
            writeField(file, "name", entry.name);
            writeField(file, "created", entry.created);
            writeField(file, "source", entry.source);
            writeField(file, "expires", entry.expires);
            writeLastField(file, "reason", entry.reason);
            if (i + 1 < self.entries.items.len) {
                file.writeAll("  },\n") catch return;
            } else {
                file.writeAll("  }\n") catch return;
            }
        }
        file.writeAll("]\n") catch return;
    }

    fn writeField(file: std.fs.File, key: []const u8, val: []const u8) void {
        var buf: [512]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "    \"{s}\": \"{s}\",\n", .{ key, val }) catch return;
        file.writeAll(written) catch {};
    }

    fn writeLastField(file: std.fs.File, key: []const u8, val: []const u8) void {
        var buf: [512]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "    \"{s}\": \"{s}\"\n", .{ key, val }) catch return;
        file.writeAll(written) catch {};
    }

    fn getStr(obj: std.json.ObjectMap, key: []const u8) []const u8 {
        const val = obj.get(key) orelse return "";
        return switch (val) {
            .string => |s| s,
            else => "",
        };
    }
};
