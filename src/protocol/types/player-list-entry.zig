const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Uuid = @import("uuid.zig").Uuid;
const ClientData = @import("../login/types.zig").ClientData;
const SerializedSkin = @import("serialized-skin.zig").SerializedSkin;

pub const PlayerListEntry = struct {
    uuid: []const u8,
    entityUniqueId: i64 = 0,
    username: []const u8 = "",
    xuid: []const u8 = "",
    platformChatId: []const u8 = "",
    buildPlatform: i32 = 0,
    skin: ?*const ClientData = null,
    teacher: bool = false,
    host: bool = false,
    subClient: bool = false,

    pub fn writeAdd(stream: *BinaryStream, entry: PlayerListEntry, allocator: std.mem.Allocator) !void {
        try Uuid.write(stream, entry.uuid);
        try stream.writeZigZong(entry.entityUniqueId);
        try stream.writeVarString(entry.username);
        try stream.writeVarString(entry.xuid);
        try stream.writeVarString(entry.platformChatId);
        try stream.writeInt32(entry.buildPlatform, .Little);
        if (entry.skin) |skin| {
            try SerializedSkin.write(stream, skin, allocator);
        }
        try stream.writeBool(entry.teacher);
        try stream.writeBool(entry.host);
        try stream.writeBool(entry.subClient);
        try stream.writeInt32(0, .Little);
    }

    pub fn writeRemove(stream: *BinaryStream, entry: PlayerListEntry) !void {
        try Uuid.write(stream, entry.uuid);
    }
};
