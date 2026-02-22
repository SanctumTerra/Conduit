const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const Uuid = @import("../types/uuid.zig").Uuid;
const ClientData = @import("../login/types.zig").ClientData;
const SerializedSkin = @import("../types/serialized-skin.zig").SerializedSkin;

pub const PlayerSkinPacket = struct {
    uuid: []const u8,
    skin: *const ClientData,

    pub fn serialize(self: *const PlayerSkinPacket, stream: *BinaryStream, allocator: std.mem.Allocator) ![]const u8 {
        try stream.writeVarInt(Packet.PlayerSkin);
        try Uuid.write(stream, self.uuid);
        try SerializedSkin.write(stream, self.skin, allocator);
        try stream.writeVarString("");
        try stream.writeVarString("");
        try stream.writeBool(self.skin.trusted_skin);
        return stream.getBuffer();
    }
};
