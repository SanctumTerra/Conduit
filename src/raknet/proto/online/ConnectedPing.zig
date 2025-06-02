const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const ConnectedPing = struct {
    timestamp: i64,

    pub fn init(timestamp: i64) ConnectedPing {
        return .{ .timestamp = timestamp };
    }

    pub fn serialize(self: *const ConnectedPing) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ConnectedPing, .Big);
        stream.writeInt64(self.timestamp, .Big);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connected ping: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) ConnectedPing {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();

        _ = stream.readVarInt(.Big);
        const timestamp = stream.readInt64(.Big);

        return .{ .timestamp = timestamp };
    }
};
