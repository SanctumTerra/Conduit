pub const CompressionMethod = enum(u8) {
    Zlib = 0,
    Snappy = 1,
    NotPresent = 2,
    None = 0xFF,
    _,
};
