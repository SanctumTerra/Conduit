const Protocol = @import("protocol");

pub const CompressionOptions = struct {
    compressionMethod: Protocol.CompressionMethod,
    compressionThreshold: u16,
};
