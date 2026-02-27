const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const Uuid = @import("../types/uuid.zig").Uuid;

pub const CommandOutputMessage = struct {
    success: bool,
    message: []const u8,
    parameters: []const []const u8,
};

pub const CommandOutputPacket = struct {
    origin_type: []const u8,
    uuid: [16]u8,
    request_id: []const u8,
    player_unique_id: i64,
    output_type: []const u8,
    success_count: u32,
    messages: []const CommandOutputMessage,

    pub fn serialize(self: *CommandOutputPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.CommandOutput);

        try stream.writeVarString(self.origin_type);
        try Uuid.write(stream, &self.uuid);
        try stream.writeVarString(self.request_id);
        try stream.writeInt64(self.player_unique_id, .Little);

        try stream.writeVarString(self.output_type);
        try stream.writeUint32(self.success_count, .Little);

        try stream.writeVarInt(@intCast(self.messages.len));
        for (self.messages) |msg| {
            try stream.writeVarString(msg.message);
            try stream.writeBool(msg.success);
            try stream.writeVarInt(@intCast(msg.parameters.len));
            for (msg.parameters) |param| {
                try stream.writeVarString(param);
            }
        }

        try stream.writeBool(false);

        return stream.getBuffer();
    }
};
