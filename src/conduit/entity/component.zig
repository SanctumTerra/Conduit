const std = @import("std");

pub const ComponentMap = struct {
    map: std.StringHashMap(*anyopaque),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ComponentMap {
        return .{
            .map = std.StringHashMap(*anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComponentMap) void {
        self.map.deinit();
    }

    pub fn put(self: *ComponentMap, identifier: []const u8, ptr: *anyopaque) !void {
        try self.map.put(identifier, ptr);
    }

    pub fn get(self: *const ComponentMap, identifier: []const u8) ?*anyopaque {
        return self.map.get(identifier);
    }

    pub fn contains(self: *const ComponentMap, identifier: []const u8) bool {
        return self.map.contains(identifier);
    }
};

pub fn EntityComponent(comptime config: struct {
    identifier: []const u8,
    Data: type,
}) type {
    return struct {
        pub const identifier = config.identifier;
        pub const Data = config.Data;

        data: config.Data,

        pub fn init(data: config.Data) @This() {
            return .{ .data = data };
        }
    };
}
