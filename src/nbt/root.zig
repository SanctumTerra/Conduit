pub const TagType = @import("./tags/tag-type.zig").TagType;
pub const ReadWriteOptions = @import("./tags/read-write-options.zig").ReadWriteOptions;

pub const ByteTag = @import("./tags/byte-tag.zig").ByteTag;
pub const ShortTag = @import("./tags/short-tag.zig").ShortTag;
pub const IntTag = @import("./tags/int-tag.zig").IntTag;
pub const LongTag = @import("./tags/long-tag.zig").LongTag;
pub const FloatTag = @import("./tags/float-tag.zig").FloatTag;
pub const DoubleTag = @import("./tags/double-tag.zig").DoubleTag;
pub const StringTag = @import("./tags/string-tag.zig").StringTag;

pub const ByteListTag = @import("./tags/byte-list-tag.zig").ByteListTag;
pub const IntListTag = @import("./tags/int-list-tag.zig").IntListTag;
pub const LongListTag = @import("./tags/long-list-tag.zig").LongListTag;
pub const ListTag = @import("./tags/list-tag.zig").ListTag;

pub const CompoundTag = @import("./tags/compound-tag.zig").CompoundTag;
pub const EndTag = @import("./tags/end-tag.zig").EndTag;

pub const Tag = @import("./tags/tag.zig").Tag;

const BinaryStream = @import("BinaryStream").BinaryStream;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
