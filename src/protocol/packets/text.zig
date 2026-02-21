const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ResourcePackDescriptor = @import("../types/resource-pack-descriptor.zig").ResourcePackDescriptor;
const Packet = @import("../root.zig").Packet;
const TextType = @import("../root.zig").TextType;

pub const TextPacket = struct {
    textType: TextType,
    needsTranslation: bool = false,
    sourceName: []const u8 = "",
    message: []const u8,
    parameters: []const []const u8 = &[_][]const u8{},
    xuid: []const u8 = "",
    platformChatId: []const u8 = "",
    filteredMessage: ?[]const u8 = null,

    pub fn serialize(self: *TextPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.Text);
        try stream.writeBool(self.needsTranslation);

        const category: u8 = switch (self.textType) {
            .Raw, .Tip, .System, .ObjectWhisper, .ObjectAnnouncement, .Object => 0,
            .Chat, .Whisper, .Announcement => 1,
            .Translation, .Popup, .JukeboxPopup => 2,
        };
        try stream.writeUint8(category);
        try stream.writeUint8(@intFromEnum(self.textType));

        switch (self.textType) {
            .Chat, .Whisper, .Announcement => {
                try stream.writeVarString(self.sourceName);
                try stream.writeVarString(self.message);
            },
            .Raw, .Tip, .System, .Object, .ObjectWhisper, .ObjectAnnouncement => {
                try stream.writeVarString(self.message);
            },
            .Translation, .Popup, .JukeboxPopup => {
                try stream.writeVarString(self.message);
                try stream.writeVarInt(@intCast(self.parameters.len));
                for (self.parameters) |param| {
                    try stream.writeVarString(param);
                }
            },
        }

        try stream.writeVarString(self.xuid);
        try stream.writeVarString(self.platformChatId);

        if (self.filteredMessage) |filtered| {
            try stream.writeBool(true);
            try stream.writeVarString(filtered);
        } else {
            try stream.writeBool(false);
        }

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !TextPacket {
        _ = try stream.readVarInt();
        const needsTranslation = try stream.readBool();
        _ = try stream.readUint8();
        const textType: TextType = @enumFromInt(try stream.readUint8());

        var sourceName: []const u8 = "";
        var message: []const u8 = "";
        var parameters: []const []const u8 = &[_][]const u8{};

        switch (textType) {
            .Chat, .Whisper, .Announcement => {
                sourceName = try stream.readVarString();
                message = try stream.readVarString();
            },
            .Raw, .Tip, .System, .Object, .ObjectWhisper, .ObjectAnnouncement => {
                message = try stream.readVarString();
            },
            .Translation, .Popup, .JukeboxPopup => {
                message = try stream.readVarString();
                const count = try stream.readVarInt();
                if (count > 0 and count < 128) {
                    var params: [128][]const u8 = undefined;
                    for (0..count) |i| {
                        params[i] = try stream.readVarString();
                    }
                    parameters = params[0..count];
                }
            },
        }

        const xuid = try stream.readVarString();
        const platformChatId = try stream.readVarString();

        var filteredMessage: ?[]const u8 = null;
        const hasFiltered = try stream.readBool();
        if (hasFiltered) {
            filteredMessage = try stream.readVarString();
        }

        return TextPacket{
            .textType = textType,
            .needsTranslation = needsTranslation,
            .sourceName = sourceName,
            .message = message,
            .parameters = parameters,
            .xuid = xuid,
            .platformChatId = platformChatId,
            .filteredMessage = filteredMessage,
        };
    }
};
