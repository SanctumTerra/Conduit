const std = @import("std");
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;
const Tag = NBT.Tag;

pub const ItemComponentMap = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMapUnmanaged(Tag),

    pub fn init(allocator: std.mem.Allocator) ItemComponentMap {
        return .{
            .allocator = allocator,
            .entries = .{},
        };
    }

    pub fn deinit(self: *ItemComponentMap) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn get(self: *const ItemComponentMap, identifier: []const u8) ?Tag {
        return self.entries.get(identifier);
    }

    pub fn getCompound(self: *const ItemComponentMap, identifier: []const u8) ?CompoundTag {
        const tag = self.entries.get(identifier) orelse return null;
        if (tag != .Compound) return null;
        return tag.Compound;
    }

    pub fn set(self: *ItemComponentMap, identifier: []const u8, tag: Tag) !void {
        try self.entries.put(self.allocator, identifier, tag);
    }

    pub fn contains(self: *const ItemComponentMap, identifier: []const u8) bool {
        return self.entries.contains(identifier);
    }

    pub fn count(self: *const ItemComponentMap) usize {
        return self.entries.count();
    }
};
