const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const CompressionMethod = @import("../root.zig").CompressionMethod;

pub const NetworkSettings = struct {
    compressionThreshold: u16,
    compressionMethod: CompressionMethod,
    clientThrottle: bool,
    clientThreshold: u8,
    clientScalar: f32,

    pub fn serialize(self: *NetworkSettings, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.NetworkSettings);
        try stream.writeUint16(self.compressionThreshold, .Little);
        try stream.writeUint16(@intFromEnum(self.compressionMethod), .Little);
        try stream.writeBool(self.clientThrottle);
        try stream.writeUint8(self.clientThreshold);
        try stream.writeFloat32(self.clientScalar, .Little);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !NetworkSettings {
        _ = try stream.readVarInt();
        const compressionThreshold = try stream.readUint16(.Little);
        const compressionMethod = try stream.readUint16(.Little);
        const clientThrottle = try stream.readBool();
        const clientThreshold = try stream.readUint8();
        const clientScalar = try stream.readFloat32(.Little);

        return NetworkSettings{
            .compressionThreshold = compressionThreshold,
            .compressionMethod = @enumFromInt(compressionMethod),
            .clientThrottle = clientThrottle,
            .clientThreshold = clientThreshold,
            .clientScalar = clientScalar,
        };
    }
};
