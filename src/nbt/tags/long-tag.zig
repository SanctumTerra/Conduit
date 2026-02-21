const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const VarInt = @import("BinaryStream").VarInt;
const ZigZong = @import("BinaryStream").ZigZong;
const Int64 = @import("BinaryStream").Int64;
const Int16 = @import("BinaryStream").Int16;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

pub const LongTag = struct {
    pub const tag_type: TagType = .Long;

    value: i64,
    name: ?[]const u8,

    pub fn init(value: i64, name: ?[]const u8) LongTag {
        return .{
            .value = value,
            .name = name,
        };
    }

    pub fn deinit(self: LongTag, allocator: std.mem.Allocator) void {
        if (self.name) |n| {
            allocator.free(n);
        }
    }

    pub fn toJSON(self: LongTag, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{}n", .{self.value});
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) !LongTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.Long)) {
                return error.InvalidTagType;
            }
        }

        const name = try readName(stream, allocator, options);
        const value: i64 = if (options.varint)
            try ZigZong.read(stream)
        else
            try Int64.read(stream, options.endian);

        return LongTag{
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

    pub fn write(stream: *BinaryStream, value: LongTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.Long));
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
            try ZigZong.write(stream, value.value);
        } else {
            try Int64.write(stream, value.value, .Little);
        }
    }
};
