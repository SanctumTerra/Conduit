const std = @import("std");
const Protocol = @import("protocol");
const Attribute = Protocol.Attribute;
const AttributeName = Protocol.AttributeName;

pub const Attributes = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(AttributeName, Attribute),
    dirty: std.AutoHashMap(AttributeName, void),

    pub fn init(allocator: std.mem.Allocator) Attributes {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(AttributeName, Attribute).init(allocator),
            .dirty = std.AutoHashMap(AttributeName, void).init(allocator),
        };
    }

    pub fn deinit(self: *Attributes) void {
        var it = self.map.valueIterator();
        while (it.next()) |attr| {
            @constCast(attr).deinit();
        }
        self.map.deinit();
        self.dirty.deinit();
    }

    pub fn registerWithCurrent(self: *Attributes, name: AttributeName, min: f32, max: f32, current: f32, default: f32) !void {
        var attr = Attribute.create(self.allocator, name, min, max, current, default);
        errdefer attr.deinit();
        try self.map.put(name, attr);
        try self.dirty.put(name, {});
    }

    pub fn register(self: *Attributes, name: AttributeName, min: f32, max: f32, default: f32) !void {
        try self.registerWithCurrent(name, min, max, default, default);
    }

    pub fn get(self: *const Attributes, name: AttributeName) ?Attribute {
        return self.map.get(name);
    }

    pub fn getCurrent(self: *const Attributes, name: AttributeName) ?f32 {
        if (self.map.get(name)) |attr| return attr.current;
        return null;
    }

    pub fn setCurrent(self: *Attributes, name: AttributeName, value: f32) void {
        if (self.map.getPtr(name)) |attr| {
            attr.setCurrent(value);
            self.dirty.put(name, {}) catch {};
        }
    }

    pub fn setMax(self: *Attributes, name: AttributeName, value: f32) void {
        if (self.map.getPtr(name)) |attr| {
            attr.setMax(value);
            self.dirty.put(name, {}) catch {};
        }
    }

    pub fn reset(self: *Attributes, name: AttributeName) void {
        if (self.map.getPtr(name)) |attr| {
            attr.reset();
            self.dirty.put(name, {}) catch {};
        }
    }

    pub fn isDirty(self: *const Attributes) bool {
        return self.dirty.count() > 0;
    }

    pub fn collectDirty(self: *Attributes, allocator: std.mem.Allocator) !std.ArrayList(Attribute) {
        var list = std.ArrayList(Attribute){
            .items = &[_]Attribute{},
            .capacity = 0,
        };
        errdefer list.deinit(allocator);

        var it = self.dirty.keyIterator();
        while (it.next()) |name| {
            if (self.map.get(name.*)) |attr| {
                try list.append(allocator, attr);
            }
        }
        self.dirty.clearRetainingCapacity();
        return list;
    }

    pub fn collectAll(self: *const Attributes, allocator: std.mem.Allocator) !std.ArrayList(Attribute) {
        var list = std.ArrayList(Attribute){
            .items = &[_]Attribute{},
            .capacity = 0,
        };
        errdefer list.deinit(allocator);

        var it = self.map.valueIterator();
        while (it.next()) |attr| {
            try list.append(allocator, attr.*);
        }
        return list;
    }
};
