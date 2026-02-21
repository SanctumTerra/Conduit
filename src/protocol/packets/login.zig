const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const Login = struct {
    protocol: i32,
    identity: []const u8,
    client: []const u8,

    pub fn serialize(self: *Login, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.Login);
        try stream.writeInt32(self.protocol, .Big);
        try stream.writeVarInt(self.client.len + self.identity.len + 8);
        try stream.writeString32(self.identity, .Little);
        try stream.writeString32(self.client, .Little);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !Login {
        _ = try stream.readVarInt();
        const protocol = try stream.readInt32(.Big);
        _ = try stream.readVarInt();
        const identity = try stream.readString32(.Little);
        const client = try stream.readString32(.Little);

        return Login{
            .protocol = protocol,
            .identity = identity,
            .client = client,
        };
    }
};
