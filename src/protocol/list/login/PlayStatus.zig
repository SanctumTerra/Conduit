const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;
const PlayStatusEnum = @import("types/PlayStatus.zig").PlayStatus;

pub const PlayStatus = struct {
    status: PlayStatusEnum,

    pub fn init(status: PlayStatusEnum) PlayStatus {
        return .{ .status = status };
    }

    pub fn serialize(self: *const PlayStatus) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.PlayStatus, .Big);
        stream.writeInt32(@intFromEnum(self.status), .Big);
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize play status: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) PlayStatus {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readVarInt(.Big);
        const status = stream.readInt32(.Big);
        const status_enum: PlayStatusEnum = switch (status) {
            0 => .LoginSuccess,
            1 => .FailedClient,
            2 => .FailedServer,
            3 => .PlayerSpawn,
            4 => .FailedInvalidTenant,
            5 => .FailedVanillaEdu,
            6 => .FailedIncompatible,
            7 => .FailedServerFull,
            8 => .FailedEditorVanillaMismatch,
            9 => .FailedVanillaEditorMismatch,
            else => .FailedClient,
        };
        return .{ .status = status_enum };
    }
};
