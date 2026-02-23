const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const PacketViolationWarningPacket = struct {
    violation_type: i32,
    severity: i32,
    packet_id: i32,
    context: []const u8,

    pub fn deserialize(stream: *BinaryStream) !PacketViolationWarningPacket {
        _ = try stream.readVarInt();
        const violation_type = try stream.readZigZag();
        const severity = try stream.readZigZag();
        const packet_id = try stream.readZigZag();
        const context = try stream.readVarString();
        return .{
            .violation_type = violation_type,
            .severity = severity,
            .packet_id = packet_id,
            .context = context,
        };
    }
};
