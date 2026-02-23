const std = @import("std");

pub const EntityType = struct {
    identifier: []const u8,
    network_id: i32,
    components: []const []const u8,
    tags: []const []const u8,

    pub fn init(identifier: []const u8, network_id: i32, components: []const []const u8, tags: []const []const u8) EntityType {
        return .{
            .identifier = identifier,
            .network_id = network_id,
            .components = components,
            .tags = tags,
        };
    }

    pub fn hasComponent(self: *const EntityType, component: []const u8) bool {
        for (self.components) |c| {
            if (std.mem.eql(u8, c, component)) return true;
        }
        return false;
    }

    pub fn hasTag(self: *const EntityType, tag: []const u8) bool {
        for (self.tags) |t| {
            if (std.mem.eql(u8, t, tag)) return true;
        }
        return false;
    }
};
