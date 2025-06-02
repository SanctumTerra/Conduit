const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const ConnectionRequest = struct {
    guid: i64,
    timestamp: i64,
    use_security: bool,

    pub fn init(guid: i64, timestamp: i64, use_security: bool) ConnectionRequest {
        return .{ .guid = guid, .timestamp = timestamp, .use_security = use_security };
    }

    pub fn serialize(self: *ConnectionRequest) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ConnectionRequest, .Big);
        stream.writeInt64(self.guid, .Big);
        stream.writeInt64(self.timestamp, .Big);
        stream.writeBool(self.use_security);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize connection request: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) ConnectionRequest {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readVarInt(.Big);
        const guid = stream.readInt64(.Big);
        const timestamp = stream.readInt64(.Big);
        const use_security = stream.readBool();

        return .{ .guid = guid, .timestamp = timestamp, .use_security = use_security };
    }
};
