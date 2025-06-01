const Callocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;

pub const UnconnectedPing = struct {
    timestamp: i64,
    guid: i64,

    pub fn init(timestamp: i64, guid: i64) UnconnectedPing {
        return .{ .timestamp = timestamp, .guid = guid };
    }

    pub fn deinit(self: *UnconnectedPing) void {
        self.timestamp = 0;
        self.guid = 0;
    }

    pub fn serialize(self: *UnconnectedPing) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.UnconnectedPing);
        stream.writeInt64(self.timestamp, .Big);
        stream.writeMagic();
        stream.writeInt64(self.guid, .Big);
        const payload = stream.toOwnedSlice();
        defer Callocator.get().free(payload);
        return payload;
    }

    pub fn deserialize(data: []const u8) UnconnectedPing {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readUint8();
        const timestamp = stream.readInt64(.Big);
        stream.skip(16);
        const guid = stream.readInt64(.Big);
        return .{ .timestamp = timestamp, .guid = guid };
    }
};
