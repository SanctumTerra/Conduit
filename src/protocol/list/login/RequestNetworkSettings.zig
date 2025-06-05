const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const RequestNetworkSettings = struct {
    protocol: i32,

    pub fn init(protocol: i32) RequestNetworkSettings {
        return .{ .protocol = protocol };
    }

    pub fn serialize(self: *const RequestNetworkSettings) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.RequestNetworkSettings, .Big);
        stream.writeInt32(self.protocol, .Big);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize request network settings: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) RequestNetworkSettings {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();

        _ = stream.readVarInt(.Big);
        const protocol = stream.readInt32(.Big);

        return .{ .protocol = protocol };
    }
};
