const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const InputData = @import("../enums/input-data.zig").InputData;

pub const PlayerAuthInputData = struct {
    flags: u64,

    pub fn init(flags: u64) PlayerAuthInputData {
        return PlayerAuthInputData{ .flags = flags };
    }

    pub fn setFlag(self: *PlayerAuthInputData, flag: InputData, value: bool) void {
        const flag_value: u64 = @intFromEnum(flag);
        const flag_bit: u64 = @as(u64, 1) << @intCast(flag_value);

        if (value) {
            self.flags |= flag_bit;
        } else {
            self.flags &= ~flag_bit;
        }
    }

    pub fn hasFlag(self: PlayerAuthInputData, flag: InputData) bool {
        const flag_value: u64 = @intFromEnum(flag);
        const flag_bit: u64 = @as(u64, 1) << @intCast(flag_value);
        return (self.flags & flag_bit) != 0;
    }

    pub fn read(stream: *BinaryStream) !PlayerAuthInputData {
        const flags: u64 = @intCast(try stream.readVarLong());
        return PlayerAuthInputData{ .flags = flags };
    }

    pub fn write(stream: *BinaryStream, value: PlayerAuthInputData) !void {
        try stream.writeVarLong(@intCast(value.flags));
    }
};
