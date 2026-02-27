const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const Uuid = @import("../types/uuid.zig").Uuid;

pub const CommandRequestPacket = struct {
    command_line: []const u8,
    origin_type: []const u8,
    uuid: [16]u8,
    request_id: []const u8,
    player_unique_id: i64,
    internal: bool,
    version: []const u8,

    pub fn deserialize(stream: *BinaryStream) !CommandRequestPacket {
        _ = try stream.readVarInt();
        const command_line = try stream.readVarString();

        const origin_type = try stream.readVarString();

        const uuid_slice = Uuid.read(stream);
        var uuid: [16]u8 = undefined;
        @memcpy(&uuid, uuid_slice[0..16]);

        const request_id = try stream.readVarString();
        const player_unique_id = try stream.readInt64(.Little);

        const internal = try stream.readBool();
        const version = try stream.readVarString();

        return CommandRequestPacket{
            .command_line = command_line,
            .origin_type = origin_type,
            .uuid = uuid,
            .request_id = request_id,
            .player_unique_id = player_unique_id,
            .internal = internal,
            .version = version,
        };
    }
};
