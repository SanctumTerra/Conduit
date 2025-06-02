const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const ConnectedPong = struct {
    timestamp: i64,
    pong_timestamp: i64,

    pub fn init(timestamp: i64, pong_timestamp: i64) ConnectedPong {
        return .{ .timestamp = timestamp, .pong_timestamp = pong_timestamp };
    }

    pub fn serialize(self: *const ConnectedPong) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ConnectedPong, .Big);
        stream.writeInt64(self.timestamp, .Big);
        stream.writeInt64(self.pong_timestamp, .Big);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connected pong: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) ConnectedPong {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();

        _ = stream.readVarInt(.Big);
        const timestamp = stream.readInt64(.Big);
        const pong_timestamp = stream.readInt64(.Big);

        return .{ .timestamp = timestamp, .pong_timestamp = pong_timestamp };
    }
};
