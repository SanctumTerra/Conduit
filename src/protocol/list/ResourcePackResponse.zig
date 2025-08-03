pub const ResourcePackResponse = struct {
    status: ResourcePackResponseEnum,

    pub fn serialize(self: *ResourcePackResponse, allocator: std.mem.Allocator) ![]const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ResourcePackResponse);
        stream.writeUint8(@as(u8, @intCast(@intFromEnum(self.status))));
        stream.writeUint16(0, .Little);

        return stream.getBufferOwned(allocator);
    }

    pub fn deserialize(data: []const u8) !ResourcePackResponse {
        var stream = BinaryStream.init(CAllocator.get(), data, 0);
        defer stream.deinit();

        // Skip packet ID (already consumed by packet handler)
        _ = stream.readVarInt();

        const status_value = stream.readUint8();
        const status = @as(ResourcePackResponseEnum, @enumFromInt(status_value));

        // Skip the uint16 field
        _ = stream.readUint16(.Little);

        return ResourcePackResponse{
            .status = status,
        };
    }
};

const ResourcePackResponseEnum = @import("../enums/ResourcePackResponse.zig").ResourcePackResponse;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packets = @import("../enums/Packets.zig").Packets;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const std = @import("std");
