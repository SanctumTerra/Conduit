const Callocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Server = @import("../../Server.zig");
const Logger = @import("Logger").Logger;

pub const ConnectionRequest1 = struct {
    /// Usually 11, sometimes still 10 :skull:
    protocol: u16,
    mtu_size: u16,

    pub fn init(protocol: u16, mtu_size: u16) ConnectionRequest1 {
        return .{ .protocol = protocol, .mtu_size = mtu_size };
    }

    pub fn deinit(self: *ConnectionRequest1) void {
        self.timestamp = 0;
        self.guid = 0;
    }

    pub fn serialize(self: *ConnectionRequest1) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.OpenConnectionRequest1);
        stream.writeMagic();
        stream.writeUint8(self.protocol);
        const current_size = @as(u16, @intCast(stream.binary.items.len));
        const padding_size = self.mtu_size - Server.UDP_HEADER_SIZE - current_size;
        const zeros = Callocator.get().alloc(u8, padding_size) catch @panic("Failed to allocate padding");
        defer Callocator.get().free(zeros);
        @memset(zeros, 0);
        stream.write(zeros);
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connection request 1: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) ConnectionRequest1 {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        stream.skip(1);
        stream.skip(16);
        const protocol = stream.readUint8();
        var mtu_size = @as(u16, @intCast(stream.buffer.items.len));
        if (mtu_size + Server.UDP_HEADER_SIZE <= Server.MAX_MTU_SIZE) {
            mtu_size = mtu_size + Server.UDP_HEADER_SIZE;
        } else {
            mtu_size = Server.MAX_MTU_SIZE;
        }
        return .{ .protocol = protocol, .mtu_size = mtu_size };
    }
};
