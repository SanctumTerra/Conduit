const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const ZigZag = @import("BinaryStream").ZigZag;
const Int32 = @import("BinaryStream").Int32;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

pub const IntTag = struct {
    pub const tag_type: TagType = .Int;

    value: i32,
    name: ?[]const u8,

    pub fn init(value: i32, name: ?[]const u8) IntTag {
        return .{
            .value = value,
            .name = name,
        };
    }

    pub fn deinit(self: IntTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }
    }

    pub fn toJSON(self: IntTag) i32 {
        return self.value;
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !IntTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.Int)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);

        const value: i32 = if (options.varint)
            try ZigZag.read(stream)
        else
            try Int32.read(stream, options.endian);

        return IntTag{
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

    pub fn write(stream: *BinaryStream, value: IntTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.Int));
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

        if (options.varint) {
            try ZigZag.write(stream, value.value);
        } else {
            try Int32.write(stream, value.value, .Little);
        }
    }
};
