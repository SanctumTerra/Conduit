const Callocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Server = @import("../../Server.zig");
const Logger = @import("Logger").Logger;
const Address = @import("../Address.zig").Address;

pub const ConnectionReply2 = struct {
    guid: i64,
    address: Address,
    mtu: u16,
    encryption_enabled: bool,

    pub fn init(guid: i64, address: Address, mtu: u16, encryption_enabled: bool) ConnectionReply2 {
        return .{ .guid = guid, .address = address, .mtu = mtu, .encryption_enabled = encryption_enabled };
    }

    pub fn serialize(self: *ConnectionReply2) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.OpenConnectionReply2);
        stream.writeMagic();
        stream.writeInt64(self.guid, .Big);
        const address_buffer = self.address.write(Callocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize address: {}", .{err});
            return &[_]u8{};
        };
        stream.write(address_buffer);
        defer Callocator.get().free(address_buffer);
        stream.writeUint16(self.mtu, .Big);
        stream.writeBool(self.encryption_enabled);
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connection reply 2: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) ConnectionReply2 {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        stream.skip(1);
        stream.skip(16);
        const guid = stream.readInt64(.Big);
        const address = Address.read(&stream, Callocator.get()) catch {
            Logger.ERROR("Failed to deserialize address", .{});
            return .{ .guid = 0, .address = Address.init(0, &[_]u8{}, 0), .mtu = 0, .encryption_enabled = false };
        };
        const mtu = stream.readUint16(.Big);
        const encryption_enabled = stream.readBool();
        return .{ .guid = guid, .address = address, .mtu = mtu, .encryption_enabled = encryption_enabled };
    }
};
