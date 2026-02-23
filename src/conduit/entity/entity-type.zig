const std = @import("std");
const ComponentMap = @import("./metadata/component.zig").ComponentMap;

pub const EntityType = struct {
    identifier: []const u8,
    network_id: i32,
    components: ComponentMap,
    tags: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, identifier: []const u8, network_id: i32, tags: []const []const u8) EntityType {
        return .{
            .identifier = identifier,
            .network_id = network_id,
            .components = ComponentMap.init(allocator),
            .tags = tags,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EntityType) void {
        self.components.deinit();
    }

    pub fn addComponent(self: *EntityType, comptime C: type, component: *C) !void {
        try self.components.put(C.identifier, @ptrCast(component));
    }

    pub fn getComponent(self: *const EntityType, comptime C: type) ?*const C {
        const raw = self.components.get(C.identifier) orelse return null;
        return @ptrCast(@alignCast(raw));
    }

    pub fn hasComponent(self: *const EntityType, comptime C: type) bool {
        return self.components.contains(C.identifier);
    }

    pub fn hasTag(self: *const EntityType, tag: []const u8) bool {
        for (self.tags) |t| {
            if (std.mem.eql(u8, t, tag)) return true;
        }
        return false;
    }
};
