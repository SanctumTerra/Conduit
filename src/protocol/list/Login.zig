pub const Login = struct {
    pub const Self = @This();
    protocol: i32,
    identity: []const u8,
    client: []const u8,

    pub fn init(protocol: i32, identity: []const u8, client: []const u8) Self {
        return Self{
            .protocol = protocol,
            .identity = identity,
            .client = client,
        };
    }

    pub fn serialize(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        VarInt.write(&stream, Packets.Login);
        Int32.write(&stream, self.protocol, .Big);
        VarInt.write(&stream, @as(u32, @intCast(self.identity.len)) + @as(u32, @intCast(self.client.len)) + 8);

        String32.write(&stream, self.identity, .Little);
        String32.write(&stream, self.client, .Little);
        return stream.getBufferOwned(allocator);
    }

    /// Note! The return value "identity" and "client" are copies, and the caller is responsible for freeing them.
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !Self {
        var stream = BinaryStream.init(allocator, data, null);
        defer stream.deinit();
        _ = VarInt.read(&stream);
        const protocol = Int32.read(&stream, .Big);
        _ = VarInt.read(&stream);
        const identity = String32.read(&stream, .Little);
        const client = String32.read(&stream, .Little);

        const copy_identity = try allocator.dupe(u8, identity);
        const copy_client = try allocator.dupe(u8, client);
        return Self{ .protocol = protocol, .identity = copy_identity, .client = copy_client };
    }
};

test "Login" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const packet = Login.init(818, "eyasdcasdcasdcasd", "eyfacfasfcas");
    const data = try packet.serialize(allocator);
    defer allocator.free(data);

    const packet2 = try Login.deserialize(allocator, data);
    defer allocator.free(packet2.identity);
    defer allocator.free(packet2.client);

    try std.testing.expectEqual(packet.protocol, packet2.protocol);
    try std.testing.expectEqualStrings(packet.identity, packet2.identity);
    try std.testing.expectEqualStrings(packet.client, packet2.client);
}

const std = @import("std");
const _BinaryStream = @import("BinaryStream");
const BinaryStream = _BinaryStream.BinaryStream;
const Packets = @import("../enums/Packets.zig").Packets;
const Int32 = _BinaryStream.Int32;
const VarInt = _BinaryStream.VarInt;
const String32 = _BinaryStream.String32;
