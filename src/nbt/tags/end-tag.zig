const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Int8 = @import("BinaryStream").Int8;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

pub const EndTag = struct {
    pub const tag_type: TagType = .End;

    pub fn init() EndTag {
        return .{};
    }

    pub fn deinit(_: EndTag, _: std.mem.Allocator) void {}

    pub fn read(stream: *BinaryStream, _: std.mem.Allocator, options: ReadWriteOptions) !EndTag {
        if (options.tag_type) {
            const read_type = try Int8.read(stream);
            if (read_type != @intFromEnum(TagType.End)) {
                return error.InvalidTagType;
            }
        }

        return EndTag{};
    }

    pub fn write(stream: *BinaryStream, _: EndTag, options: ReadWriteOptions) !void {
        if (options.tag_type) {
            try Int8.write(stream, @intFromEnum(TagType.End));
        }
    }
};
