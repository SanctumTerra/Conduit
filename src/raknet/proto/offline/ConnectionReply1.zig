const Callocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Server = @import("../../Server.zig");
const Logger = @import("Logger").Logger;

pub const ConnectionReply1 = struct {
    guid: i64,
    hasSecurity: bool,
    mtu_size: u16,

    pub fn init(guid: i64, hasSecurity: bool, mtu_size: u16) ConnectionReply1 {
        return .{ .guid = guid, .hasSecurity = hasSecurity, .mtu_size = mtu_size };
    }

    pub fn serialize(self: *ConnectionReply1) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.OpenConnectionReply1);
        stream.writeMagic();
        stream.writeInt64(self.guid, .Big);
        stream.writeBool(self.hasSecurity);
        stream.writeUint16(self.mtu_size, .Big);
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connection reply 1: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) ConnectionReply1 {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        stream.skip(1);
        stream.skip(16);
        const guid = stream.readInt64(.Big);
        const hasSecurity = stream.readBool();
        const mtu_size = stream.readUint16(.Big);
        return .{ .guid = guid, .hasSecurity = hasSecurity, .mtu_size = mtu_size };
    }
};
