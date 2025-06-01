const Callocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Server = @import("../../Server.zig");
const Logger = @import("Logger").Logger;
const Address = @import("../Address.zig").Address;

pub const ConnectionRequest2 = struct {
    address: Address,
    mtu_size: u16,
    guid: i64,

    pub fn init(address: Address, mtu_size: u16, guid: i64) ConnectionRequest2 {
        return .{ .address = address, .mtu_size = mtu_size, .guid = guid };
    }

    pub fn serialize(self: *ConnectionRequest2) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.OpenConnectionRequest2);
        stream.writeMagic();
        const address_buffer = self.address.write(Callocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize address: {}", .{err});
            return &[_]u8{};
        };
        stream.write(address_buffer);
        defer Callocator.get().free(address_buffer);
        stream.writeUint16(self.mtu_size, .Big);
        stream.writeInt64(self.guid, .Big);
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connection request 1: {}", .{err});
            return &[_]u8{};
        };
    }

    /// DEALLOCATE THE ADDRESS AFTER USE
    pub fn deserialize(data: []const u8) ConnectionRequest2 {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        stream.skip(1);
        stream.skip(16);
        const address = Address.read(&stream, Callocator.get()) catch {
            Logger.ERROR("Failed to deserialize address", .{});
            return .{ .address = Address.init(0, &[_]u8{}, 0), .mtu_size = 0, .guid = 0 };
        };
        const mtu_size = stream.readUint16(.Big);
        const guid = stream.readInt64(.Big);
        return .{ .address = address, .mtu_size = mtu_size, .guid = guid };
    }
};
