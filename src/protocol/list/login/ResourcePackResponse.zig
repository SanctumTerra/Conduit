const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;
const ResourcePackResponseEnum = @import("types/ResourcePackResponse.zig").ResourcePackResponse;

pub const ResourcePackResponse = struct {
    status: ResourcePackResponseEnum,

    pub fn serialize(self: *ResourcePackResponse) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ResourcePackResponse, .Big);
        stream.writeUint8(@as(u8, @intCast(@intFromEnum(self.status))));
        stream.writeUint16(0, .Little);

        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for pong packet");
    }

    pub fn deserialize(data: []const u8) ResourcePackResponse {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readVarInt(.Big);
        const status = stream.readUint8();
        const status_enum: ResourcePackResponseEnum = switch (status) {
            0 => .None,
            1 => .Refused,
            2 => .SendPacks,
            3 => .HaveAllPacks,
            4 => .Completed,
            else => .Completed,
        };
        _ = stream.readUint16(.Little);
        return .{ .status = status_enum };
    }
};
