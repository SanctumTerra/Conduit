const std = @import("std");
const Endian = @import("BinaryStream").Endianess;

pub const ReadWriteOptions = struct {
    name: bool = true,
    tag_type: bool = true,
    varint: bool = false,
    endian: Endian = .Little,

    pub const default: ReadWriteOptions = .{
        .name = true,
        .tag_type = true,
        .varint = false,
        .endian = .Little,
    };

    pub const no_name: ReadWriteOptions = .{
        .name = false,
        .tag_type = true,
        .varint = false,
        .endian = .Little,
    };

    pub const no_type: ReadWriteOptions = .{
        .name = true,
        .tag_type = false,
        .varint = false,
        .endian = .Little,
    };

    pub const network: ReadWriteOptions = .{
        .name = true,
        .tag_type = true,
        .varint = true,
        .endian = .Little,
    };

    pub const big_endian: ReadWriteOptions = .{
        .name = true,
        .tag_type = true,
        .varint = false,
        .endian = .Big,
    };
};
