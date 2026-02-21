const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

const TagType = @import("tag-type.zig").TagType;
const ReadWriteOptions = @import("read-write-options.zig").ReadWriteOptions;

const ByteTag = @import("byte-tag.zig").ByteTag;
const ShortTag = @import("short-tag.zig").ShortTag;
const IntTag = @import("int-tag.zig").IntTag;
const LongTag = @import("long-tag.zig").LongTag;
const FloatTag = @import("float-tag.zig").FloatTag;
const DoubleTag = @import("double-tag.zig").DoubleTag;
const StringTag = @import("string-tag.zig").StringTag;
const ByteListTag = @import("byte-list-tag.zig").ByteListTag;
const IntListTag = @import("int-list-tag.zig").IntListTag;
const LongListTag = @import("long-list-tag.zig").LongListTag;
const EndTag = @import("end-tag.zig").EndTag;
const ListTag = @import("list-tag.zig").ListTag;
const CompoundTag = @import("compound-tag.zig").CompoundTag;

pub const Tag = union(TagType) {
    End: EndTag,
    Byte: ByteTag,
    Short: ShortTag,
    Int: IntTag,
    Long: LongTag,
    Float: FloatTag,
    Double: DoubleTag,
    ByteList: ByteListTag,
    String: StringTag,
    List: ListTag,
    Compound: CompoundTag,
    IntList: IntListTag,
    LongList: LongListTag,

    pub fn deinit(self: *Tag, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .End => |tag| tag.deinit(allocator),
            .Byte => |tag| tag.deinit(allocator),
            .Short => |tag| tag.deinit(allocator),
            .Int => |tag| tag.deinit(allocator),
            .Long => |tag| tag.deinit(allocator),
            .Float => |tag| tag.deinit(allocator),
            .Double => |tag| tag.deinit(allocator),
            .ByteList => |tag| tag.deinit(allocator),
            .String => |tag| tag.deinit(allocator),
            .List => |tag| tag.deinit(allocator),
            .Compound => |*tag| tag.deinit(allocator),
            .IntList => |tag| tag.deinit(allocator),
            .LongList => |tag| tag.deinit(allocator),
        }
    }

    pub fn getName(self: *const Tag) ?[]const u8 {
        return switch (self.*) {
            .End => null,
            .Byte => |tag| tag.name,
            .Short => |tag| tag.name,
            .Int => |tag| tag.name,
            .Long => |tag| tag.name,
            .Float => |tag| tag.name,
            .Double => |tag| tag.name,
            .ByteList => |tag| tag.name,
            .String => |tag| tag.name,
            .List => |tag| tag.name,
            .Compound => |tag| tag.name,
            .IntList => |tag| tag.name,
            .LongList => |tag| tag.name,
        };
    }

    pub fn getType(self: *const Tag) TagType {
        return @as(TagType, self.*);
    }

    pub fn setName(self: *Tag, name: ?[]const u8) void {
        switch (self.*) {
            .End => {},
            .Byte => |*t| t.name = name,
            .Short => |*t| t.name = name,
            .Int => |*t| t.name = name,
            .Long => |*t| t.name = name,
            .Float => |*t| t.name = name,
            .Double => |*t| t.name = name,
            .ByteList => |*t| t.name = name,
            .String => |*t| t.name = name,
            .List => |*t| t.name = name,
            .Compound => |*t| t.name = name,
            .IntList => |*t| t.name = name,
            .LongList => |*t| t.name = name,
        }
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, options: ReadWriteOptions) anyerror!Tag {
        const Int8 = @import("BinaryStream").Int8;

        const tag_type_raw = try Int8.read(stream);
        const tag_type: TagType = @enumFromInt(@as(u8, @bitCast(tag_type_raw)));
        const read_options = ReadWriteOptions{
            .name = options.name,
            .tag_type = false,
            .varint = options.varint,
            .endian = options.endian,
        };

        return readWithType(stream, allocator, tag_type, read_options);
    }

    pub fn readWithType(stream: *BinaryStream, allocator: std.mem.Allocator, tag_type: TagType, options: ReadWriteOptions) anyerror!Tag {
        return switch (tag_type) {
            .End => .{ .End = try EndTag.read(stream, allocator, options) },
            .Byte => .{ .Byte = try ByteTag.read(stream, allocator, options) },
            .Short => .{ .Short = try ShortTag.read(stream, allocator, options) },
            .Int => .{ .Int = try IntTag.read(stream, allocator, options) },
            .Long => .{ .Long = try LongTag.read(stream, allocator, options) },
            .Float => .{ .Float = try FloatTag.read(stream, allocator, options) },
            .Double => .{ .Double = try DoubleTag.read(stream, allocator, options) },
            .ByteList => .{ .ByteList = try ByteListTag.read(stream, allocator, options) },
            .String => .{ .String = try StringTag.read(stream, allocator, options) },
            .List => .{ .List = try ListTag.read(stream, allocator, options) },
            .Compound => .{ .Compound = try CompoundTag.read(stream, allocator, options) },
            .IntList => .{ .IntList = try IntListTag.read(stream, allocator, options) },
            .LongList => .{ .LongList = try LongListTag.read(stream, allocator, options) },
        };
    }

    pub fn write(self: *const Tag, stream: *BinaryStream, options: ReadWriteOptions) anyerror!void {
        switch (self.*) {
            .End => |tag| try EndTag.write(stream, tag, options),
            .Byte => |tag| try ByteTag.write(stream, tag, options),
            .Short => |tag| try ShortTag.write(stream, tag, options),
            .Int => |tag| try IntTag.write(stream, tag, options),
            .Long => |tag| try LongTag.write(stream, tag, options),
            .Float => |tag| try FloatTag.write(stream, tag, options),
            .Double => |tag| try DoubleTag.write(stream, tag, options),
            .ByteList => |tag| try ByteListTag.write(stream, tag, options),
            .String => |tag| try StringTag.write(stream, tag, options),
            .List => |tag| try ListTag.write(stream, tag, options),
            .Compound => |*tag| try CompoundTag.write(stream, tag, options),
            .IntList => |tag| try IntListTag.write(stream, tag, options),
            .LongList => |tag| try LongListTag.write(stream, tag, options),
        }
    }
};
