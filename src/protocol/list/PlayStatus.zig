const PlayStatusEnum = @import("../enums/PlayStatus.zig").PlayStatus;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packets = @import("../enums/Packets.zig").Packets;
const Logger = @import("Logger").Logger;
const std = @import("std");

pub const PlayStatus = struct {
    status: PlayStatusEnum,

    pub fn init(status: PlayStatusEnum) PlayStatus {
        return .{ .status = status };
    }

    pub fn deinit(self: *PlayStatus) void {
        _ = self;
    }

    pub fn serialize(self: *const PlayStatus, allocator: std.mem.Allocator) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(allocator, buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.PlayStatus);
        stream.writeInt32(@intFromEnum(self.status), .Big);
        return stream.getBufferOwned(allocator) catch |err| {
            Logger.ERROR("Failed to serialize play status: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8, allocator: std.mem.Allocator) PlayStatus {
        var stream = BinaryStream.init(allocator, data, 0);
        defer stream.deinit();
        _ = stream.readVarInt();
        const status = stream.readInt32(.Big);
        const status_enum: PlayStatusEnum = @enumFromInt(status);
        return .{ .status = status_enum };
    }
};
