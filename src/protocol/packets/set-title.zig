const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const TitleType = enum(i32) {
    Clear = 0,
    Reset = 1,
    SetTitle = 2,
    SetSubtitle = 3,
    SetActionBar = 4,
    SetDurations = 5,
    TitleTextObject = 6,
    SubtitleTextObject = 7,
    ActionBarTextObject = 8,
};

pub const SetTitlePacket = struct {
    title_type: TitleType,
    text: []const u8 = "",
    fade_in: i32 = 10,
    stay: i32 = 70,
    fade_out: i32 = 20,
    xuid: []const u8 = "",
    platform_online_id: []const u8 = "",
    filtered_text: []const u8 = "",

    pub fn serialize(self: *const SetTitlePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.SetTitle);
        try stream.writeInt32(@intFromEnum(self.title_type), .Little);
        try stream.writeVarString(self.text);
        try stream.writeInt32(self.fade_in, .Little);
        try stream.writeInt32(self.stay, .Little);
        try stream.writeInt32(self.fade_out, .Little);
        try stream.writeVarString(self.xuid);
        try stream.writeVarString(self.platform_online_id);
        try stream.writeVarString(self.filtered_text);
        return stream.getBuffer();
    }
};
