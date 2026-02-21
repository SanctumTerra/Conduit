const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const ZigZag = @import("BinaryStream").ZigZag;
const ZigZong = @import("BinaryStream").ZigZong;
const Int64 = @import("BinaryStream").Int64;
const Int32 = @import("BinaryStream").Int32;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

pub const LongListTag = struct {
    pub const tag_type: TagType = .LongList;

    value: []const i64,
    name: ?[]const u8,

    pub fn init(value: []const i64, name: ?[]const u8) LongListTag {
        return .{
            .value = value,
            .name = name,
        };
    }

    pub fn deinit(self: LongListTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }
        allocator.free(self.value);
    }

    pub fn toJSON(self: LongListTag, allocator: std.mem.Allocator) ![][]const u8 {
        var result = try allocator.alloc([]const u8, self.value.len);
        errdefer allocator.free(result);

        for (self.value, 0..) |v, i| {
            result[i] = try std.fmt.allocPrint(allocator, "{}n", .{v});
        }
        return result;
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !LongListTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.LongList)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);
        const length: u32 = if (options.varint)
            @bitCast(try ZigZag.read(stream))
        else
            @bitCast(try Int32.read(stream, options.endian));

        const value = try allocator.alloc(i64, length);
        errdefer allocator.free(value);

        for (0..length) |i| {
            value[i] = if (options.varint)
                try ZigZong.read(stream)
            else
                try Int64.read(stream, options.endian);
        }

        return LongListTag{
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

    pub fn write(stream: *BinaryStream, value: LongListTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.LongList));
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
                try ZigZong.write(stream, v);
            } else {
                try Int64.write(stream, v, .Little);
            }
        }
    }
};
