const std = @import("std");
const _BinaryStream = @import("BinaryStream");
const BinaryStream = _BinaryStream.BinaryStream;
const Packets = @import("../enums/Packets.zig").Packets;
const VarInt = _BinaryStream.VarInt;
const Int32 = _BinaryStream.Int32;

pub const RequestNetworkSettings = struct {
    pub const Self = @This();
    protocol: i32,

    pub fn init(protocol: i32) Self {
        return Self{
            .protocol = protocol,
        };
    }

    pub fn serialize(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        VarInt.write(&stream, Packets.RequestNetworkSettings);
        Int32.write(&stream, self.protocol, .Big);
        return stream.getBufferOwned(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) Self {
        var stream = BinaryStream.init(allocator, data, null);
        defer stream.deinit();
        _ = VarInt.read(&stream);
        const protocol = Int32.read(&stream, .Big);
        return Self{
            .protocol = protocol,
        };
    }
};

test "RequestNetworkSettings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const packet = RequestNetworkSettings.init(818);
    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    const packet2 = RequestNetworkSettings.deserialize(allocator, data);
    try std.testing.expectEqual(packet.protocol, packet2.protocol);
}
