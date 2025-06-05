const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const ClientCacheStatusPacket = struct {
    supported: bool,

    pub fn serialize(self: *ClientCacheStatusPacket) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ClientCacheStatus, .Big);
        stream.writeBool(self.supported);
        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for pong packet");
    }

    pub fn deserialize(data: []const u8) ClientCacheStatusPacket {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readVarInt(.Big);
        const supported = stream.readBool();
        return .{ .supported = supported };
    }
};
