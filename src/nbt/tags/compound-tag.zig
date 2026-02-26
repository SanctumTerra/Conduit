const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;
const Tag = @import("tag.zig").Tag;

pub const CompoundTag = struct {
    pub const tag_type: TagType = .Compound;

    value: std.StringHashMapUnmanaged(Tag),
    name: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: ?[]const u8) CompoundTag {
        return .{
            .value = .{},
            .name = name,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CompoundTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }

        var it = self.value.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.value.deinit(allocator);
    }

    pub fn get(self: *const CompoundTag, name: []const u8) ?Tag {
        return self.value.get(name);
    }

    pub fn set(self: *CompoundTag, name: []const u8, tag: Tag) !void {
        var mutable_tag = tag;

        const tag_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(tag_name);
        mutable_tag.setName(tag_name);

        try self.value.put(self.allocator, tag_name, mutable_tag);
    }

    pub fn add(self: *CompoundTag, tag: Tag) !void {
        const tag_name = tag.getName() orelse "";
        try self.value.put(self.allocator, tag_name, tag);
    }

    pub fn push(self: *CompoundTag, tags: []const Tag) !void {
        for (tags) |tag| {
            try self.add(tag);
        }
    }

    pub fn contains(self: *const CompoundTag, name: []const u8) bool {
        return self.value.contains(name);
    }

    pub fn count(self: *const CompoundTag) usize {
        return self.value.count();
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !CompoundTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.Compound)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);

        var value: std.StringHashMapUnmanaged(Tag) = .{};
        errdefer {
            var it = value.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            value.deinit(allocator);
        }

        const child_read_options = ReadWriteOptions{
            .name = true,
            .tag_type = false,
            .varint = options.varint,
            .endian = options.endian,
        };

        while (true) {
            const next_type_raw = try Int8.read(stream);
            const next_type: TagType = std.meta.intToEnum(TagType, @as(u8, @bitCast(next_type_raw))) catch return error.InvalidTagType;

            if (next_type == .End) {
                break;
            }

            const child_tag = try Tag.readWithType(stream, allocator, next_type, child_read_options);

            const child_name = child_tag.getName() orelse "";
            try value.put(allocator, child_name, child_tag);
        }

        return CompoundTag{
            .value = value,
            .name = name,
            .allocator = allocator,
        };
    }

    inline fn readName(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !?[]const u8 {
        if (!options.name) return null;

        const name_length: u16 = if (options.varint)
            @intCast(try VarInt.read(stream))
        else
            @bitCast(try Int16.read(stream, options.endian));

        if (name_length == 0) return null;

        const name_bytes = stream.read(name_length);
        return try allocator.dupe(u8, name_bytes);
    }

    pub fn write(stream: *BinaryStream, value: *const CompoundTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.Compound));
        }

        if (options.name) {
            const name_bytes = value.name orelse "";
            const name_len: u16 = @intCast(name_bytes.len);
            if (options.varint) {
                try VarInt.write(stream, @intCast(name_len));
            } else {
                try Int16.write(stream, @bitCast(name_len), .Little);
            }
            if (name_len > 0) {
                try stream.write(name_bytes);
            }
        }

        const child_options = ReadWriteOptions{
            .name = true,
            .tag_type = true,
            .varint = options.varint,
            .endian = options.endian,
        };

        var it = value.value.iterator();
        while (it.next()) |entry| {
            try entry.value_ptr.write(stream, child_options);
        }

        try Int8.write(stream, @intFromEnum(TagType.End));
    }
};
