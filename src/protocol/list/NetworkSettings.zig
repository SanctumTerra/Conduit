const std = @import("std");
const _BinaryStream = @import("BinaryStream");
const BinaryStream = _BinaryStream.BinaryStream;
const VarInt = _BinaryStream.VarInt;
const Int32 = _BinaryStream.Int32;
const UInt16 = _BinaryStream.Uint16;
const UInt8 = _BinaryStream.Uint8;
const Float32 = _BinaryStream.Float32;
const Bool = _BinaryStream.Bool;
const Packets = @import("../enums/Packets.zig").Packets;

pub const NetworkSettings = struct {
    pub const Self = @This();
    compressionThreshold: u16,
    compressionMethod: u16,
    clientThrottle: bool,
    clientThreshold: u8,
    clientScalar: f32,

    pub fn init(compressionThreshold: u16, compressionMethod: u16, clientThrottle: bool, clientThreshold: u8, clientScalar: f32) Self {
        return Self{
            .compressionThreshold = compressionThreshold,
            .compressionMethod = compressionMethod,
            .clientThrottle = clientThrottle,
            .clientThreshold = clientThreshold,
            .clientScalar = clientScalar,
        };
    }

    pub fn serialize(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        VarInt.write(&stream, Packets.NetworkSettings);
        UInt16.write(&stream, self.compressionThreshold, .Little);
        UInt16.write(&stream, self.compressionMethod, .Little);
        Bool.write(&stream, self.clientThrottle);
        UInt8.write(&stream, self.clientThreshold);
        Float32.write(&stream, self.clientScalar, .Little);
        return stream.getBufferOwned(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) Self {
        var stream = BinaryStream.init(allocator, data, null);
        defer stream.deinit();
        _ = VarInt.read(&stream);
        const compressionThreshold = UInt16.read(&stream, .Little);
        const compressionMethod = UInt16.read(&stream, .Little);
        const clientThrottle = Bool.read(&stream);
        const clientThreshold = UInt8.read(&stream);
        const clientScalar = Float32.read(&stream, .Little);
        return Self{
            .compressionThreshold = compressionThreshold,
            .compressionMethod = compressionMethod,
            .clientThrottle = clientThrottle,
            .clientThreshold = clientThreshold,
            .clientScalar = clientScalar,
        };
    }
};

test "NetworkSettings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const packet = NetworkSettings.init(1, 1, false, 10, 1.0);
    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    const packet2 = NetworkSettings.deserialize(allocator, data);
    try std.testing.expectEqual(packet.compressionThreshold, packet2.compressionThreshold);
    try std.testing.expectEqual(packet.compressionMethod, packet2.compressionMethod);
    try std.testing.expectEqual(packet.clientThrottle, packet2.clientThrottle);
    try std.testing.expectEqual(packet.clientThreshold, packet2.clientThreshold);
    try std.testing.expectEqual(packet.clientScalar, packet2.clientScalar);
}
