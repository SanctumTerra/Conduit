const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;
pub const NetworkSettings = struct {
    compressionThreshold: u16,
    compressionMethod: u16,
    clientThrottle: bool,
    clientThreshold: u8,
    clientScalar: f32,

    pub fn init(compressionThreshold: u16, compressionMethod: u16, clientThrottle: bool, clientThreshold: u8, clientScalar: f32) NetworkSettings {
        return .{ .compressionThreshold = compressionThreshold, .compressionMethod = compressionMethod, .clientThrottle = clientThrottle, .clientThreshold = clientThreshold, .clientScalar = clientScalar };
    }

    pub fn serialize(self: *const NetworkSettings) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.NetworkSettings, .Big);
        stream.writeUint16(self.compressionThreshold, .Little);
        stream.writeUint16(self.compressionMethod, .Little);
        stream.writeBool(self.clientThrottle);
        stream.writeUint8(self.clientThreshold);
        stream.writeFloat32(self.clientScalar, .Little);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize request network settings: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) NetworkSettings {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();

        _ = stream.readVarInt(.Big);
        const compressionThreshold = stream.readUint16(.Little);
        const compressionMethod = stream.readUint16(.Little);
        const clientThrottle = stream.readBool();
        const clientThreshold = stream.readUint8();
        const clientScalar = stream.readFloat32(.Little);

        return .{ .compressionThreshold = compressionThreshold, .compressionMethod = compressionMethod, .clientThrottle = clientThrottle, .clientThreshold = clientThreshold, .clientScalar = clientScalar };
    }
};
