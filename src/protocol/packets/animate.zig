const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const AnimateAction = enum(u8) {
    SwingArm = 1,
    StopSleep = 2,
    CriticalHit = 3,
    MagicCriticalHit = 4,
};

pub const AnimatePacket = struct {
    action: AnimateAction,
    runtime_entity_id: u64,
    data: f32 = 0,
    swing_source: []const u8 = "",

    pub fn serialize(self: *const AnimatePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.Animate);
        try stream.writeUint8(@intFromEnum(self.action));
        try stream.writeVarLong(self.runtime_entity_id);
        try stream.writeFloat32(self.data, .Little);
        if (self.swing_source.len > 0) {
            try stream.writeBool(true);
            try stream.writeVarString(self.swing_source);
        } else {
            try stream.writeBool(false);
        }
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !AnimatePacket {
        _ = try stream.readVarInt();
        const action_raw = try stream.readUint8();
        const action: AnimateAction = std.meta.intToEnum(AnimateAction, action_raw) catch return error.UnknownAnimateAction;
        const runtime_entity_id: u64 = @intCast(try stream.readVarLong());
        const data = try stream.readFloat32(.Little);
        var swing_source: []const u8 = "";
        const has_swing = try stream.readBool();
        if (has_swing) {
            swing_source = try stream.readVarString();
        }
        return AnimatePacket{
            .action = action,
            .runtime_entity_id = runtime_entity_id,
            .data = data,
            .swing_source = swing_source,
        };
    }
};
