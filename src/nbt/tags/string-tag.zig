const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

pub const StringTag = struct {
    pub const tag_type: TagType = .String;

    value: []const u8,
    name: ?[]const u8,

    pub fn init(value: []const u8, name: ?[]const u8) StringTag {
        return .{
            .value = value,
            .name = name,
        };
    }

    pub fn deinit(self: StringTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }
        allocator.free(self.value);
    }

    pub fn toJSON(self: StringTag) []const u8 {
        return self.value;
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !StringTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.String)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);

        const value_length: u16 = if (options.varint)
            @intCast(try VarInt.read(stream))
        else
            @bitCast(try Int16.read(stream, options.endian));

        const value: []const u8 = if (value_length > 0)
            try allocator.dupe(u8, stream.read(value_length))
        else
            try allocator.alloc(u8, 0);

        return StringTag{
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

    pub fn write(stream: *BinaryStream, value: StringTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.String));
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

        const value_len: u16 = @intCast(value.value.len);
        if (options.varint) {
            try VarInt.write(stream, @intCast(value_len));
        } else {
            try Int16.write(stream, @bitCast(value_len), .Little);
        }

        if (value_len > 0) {
            try stream.write(value.value);
        }
    }
};
