const Callocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const UnconnectedPong = struct {
    timestamp: i64,
    guid: i64,
    message: []const u8,

    pub fn init(timestamp: i64, guid: i64, message: []const u8) UnconnectedPong {
        return .{ .timestamp = timestamp, .guid = guid, .message = message };
    }

    pub fn deinit(self: *UnconnectedPong) void {
        self.timestamp = 0;
        self.guid = 0;
        self.message = "";
    }

    pub fn serialize(self: *UnconnectedPong) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.UnconnectedPong);
        stream.writeInt64(self.timestamp, .Big);
        stream.writeInt64(self.guid, .Big);
        stream.writeMagic();
        stream.writeString16(self.message, .Big);
        const payload = stream.toOwnedSlice() catch {
            Logger.ERROR("Failed to serialize unconnected pong", .{});
            return "";
        };
        return payload;
    }

    pub fn deserialize(data: []const u8) UnconnectedPong {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        stream.skip(1);
        const timestamp = stream.readInt64(.Big);
        const guid = stream.readInt64(.Big);
        stream.skip(16);
        const message = stream.readString16(.Big);
        return .{ .timestamp = timestamp, .guid = guid, .message = message };
    }
};
