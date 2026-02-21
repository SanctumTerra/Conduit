const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const ZigZag = @import("BinaryStream").ZigZag;
const Int32 = @import("BinaryStream").Int32;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

pub const IntListTag = struct {
    pub const tag_type: TagType = .IntList;

    value: []const i32,
    name: ?[]const u8,

    pub fn init(value: []const i32, name: ?[]const u8) IntListTag {
        return .{
            .value = value,
            .name = name,
        };
    }

    pub fn deinit(self: IntListTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }
        allocator.free(self.value);
    }

    pub fn toJSON(self: IntListTag) []const i32 {
        return self.value;
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !IntListTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.IntList)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);

        const length: u32 = if (options.varint)
            @bitCast(try ZigZag.read(stream))
        else
            @bitCast(try Int32.read(stream, options.endian));

        const value = try allocator.alloc(i32, length);
        errdefer allocator.free(value);

        for (0..length) |i| {
            value[i] = if (options.varint)
                try ZigZag.read(stream)
            else
                try Int32.read(stream, options.endian);
        }

        return IntListTag{
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

    pub fn write(stream: *BinaryStream, value: IntListTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.IntList));
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

        const length: i32 = @intCast(value.value.len);
        if (options.varint) {
            try ZigZag.write(stream, length);
        } else {
            try Int32.write(stream, length, .Little);
        }

        for (value.value) |v| {
            if (options.varint) {
                try ZigZag.write(stream, v);
            } else {
                try Int32.write(stream, v, .Little);
            }
        }
    }
};
