const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const ZigZag = @import("BinaryStream").ZigZag;
const Int32 = @import("BinaryStream").Int32;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;
const Tag = @import("tag.zig").Tag;

pub const ListTag = struct {
    pub const tag_type: TagType = .List;

    value: []Tag,
    name: ?[]const u8,

    pub fn init(value: []Tag, name: ?[]const u8) ListTag {
        return .{
            .value = value,
            .name = name,
        };
    }

    pub fn initEmpty(allocator: std.mem.Allocator, name: ?[]const u8) !ListTag {
        return .{
            .value = try allocator.alloc(Tag, 0),
            .name = if (name) |n| try allocator.dupe(u8, n) else null,
        };
    }

    pub fn deinit(self: ListTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }
        for (self.value) |*tag| {
            tag.deinit(allocator);
        }
        allocator.free(self.value);
    }

    pub fn getElementType(self: *const ListTag) TagType {
        if (self.value.len == 0) {
            return .Byte;
        }
        return self.value[0].getType();
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !ListTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.List)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);

        const element_type_raw = try Int8.read(stream);
        const element_type: TagType = @enumFromInt(@as(u8, @bitCast(element_type_raw)));

        const length: u32 = if (options.varint)
            @bitCast(try ZigZag.read(stream))
        else
            @bitCast(try Int32.read(stream, options.endian));

        const value = try allocator.alloc(Tag, length);
        errdefer {
            for (value) |*tag| {
                tag.deinit(allocator);
            }
            allocator.free(value);
        }

        const element_options = ReadWriteOptions{
            .name = false,
            .tag_type = false,
            .varint = options.varint,
            .endian = options.endian,
        };

        for (0..length) |i| {
            value[i] = try Tag.readWithType(stream, allocator, element_type, element_options);
        }

        return ListTag{
            .value = value,
            .name = name,
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

    pub fn write(stream: *BinaryStream, value: ListTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.List));
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

        const element_type: TagType = if (value.value.len == 0)
            .Byte
        else
            value.value[0].getType();

        try Int8.write(stream, @bitCast(@intFromEnum(element_type)));

        const length: i32 = @intCast(value.value.len);
        if (options.varint) {
            try ZigZag.write(stream, length);
        } else {
            try Int32.write(stream, length, .Little);
        }

        const element_options = ReadWriteOptions{
            .name = false,
            .tag_type = false,
            .varint = options.varint,
        };

        for (value.value) |*tag| {
            try tag.write(stream, element_options);
        }
    }
};
