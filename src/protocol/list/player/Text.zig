const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const TextType = enum(u8) { Raw = 0, Chat = 1, Translation = 2, Popup = 3, JukeboxPopup = 4, Tip = 5, System = 6, Whisper = 7, Announcement = 8, JsonWhisper = 9, Json = 10, JsonAnnouncement = 11 };

pub const Text = struct {
    text_type: TextType,
    needs_translation: bool,
    source: []const u8 = "",
    message: []const u8,
    parameters: [][]const u8,
    xuid: []const u8,
    platform_chat_id: []const u8,
    filtered: []const u8,

    pub fn serialize(self: *const Text) []const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        stream.writeVarInt(Packets.Text, .Big);
        stream.writeUint8(@intFromEnum(self.text_type));

        stream.writeBool(self.needs_translation);

        if (self.text_type == .Chat or self.text_type == .Whisper or self.text_type == .Announcement) {
            stream.writeVarString(self.source);
        }

        stream.writeVarString(self.message);

        if (self.text_type == .Translation or self.text_type == .Popup or self.text_type == .JukeboxPopup) {
            stream.writeVarInt(@as(u32, @intCast(self.parameters.len)), .Big);
            if (self.parameters.len > 0) {
                for (self.parameters) |parameter| {
                    stream.writeVarString(parameter);
                }
            }
        }

        stream.writeVarString(self.xuid);
        stream.writeVarString(self.platform_chat_id);
        stream.writeVarString(self.filtered);
        return stream.toOwnedSlice() catch {
            Logger.ERROR("Failed to allocate memory for TextPacket", .{});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) Text {
        var stream = BinaryStream.init(CAllocator.get(), data, 0);
        _ = stream.readVarInt(.Big);
        const text_type = @as(TextType, switch (stream.readUint8()) {
            0 => .Raw,
            1 => .Chat,
            2 => .Translation,
            3 => .Popup,
            4 => .JukeboxPopup,
            5 => .Tip,
            6 => .System,
            7 => .Whisper,
            8 => .Announcement,
            9 => .JsonWhisper,
            10 => .Json,
            11 => .JsonAnnouncement,
            else => .Raw,
        });
        const needs_translation = stream.readBool();
        var source: []const u8 = "";
        if (text_type == .Chat or text_type == .Whisper or text_type == .Announcement) {
            source = stream.readVarString();
        }
        const message = stream.readVarString();
        var parameters_list = std.ArrayList([]const u8).init(CAllocator.get());
        defer parameters_list.deinit();

        if (text_type == .Translation or text_type == .Popup or text_type == .JukeboxPopup) {
            const parameter_count = stream.readVarInt(.Big);
            for (0..parameter_count) |_| {
                parameters_list.append(stream.readVarString()) catch {
                    Logger.ERROR("Failed to allocate memory for TextPacket parameter string", .{});
                };
            }
        }

        const xuid = stream.readVarString();
        const platform_chat_id = stream.readVarString();
        const filtered = stream.readVarString();

        const final_parameters = parameters_list.toOwnedSlice() catch {
            Logger.ERROR("Failed to allocate memory for TextPacket parameters slice", .{});
            return Text{
                .text_type = text_type,
                .needs_translation = needs_translation,
                .source = source,
                .message = message,
                .parameters = &[_][]const u8{},
                .xuid = xuid,
                .platform_chat_id = platform_chat_id,
                .filtered = filtered,
            };
        };

        return Text{
            .text_type = text_type,
            .needs_translation = needs_translation,
            .source = source,
            .message = message,
            .parameters = final_parameters,
            .xuid = xuid,
            .platform_chat_id = platform_chat_id,
            .filtered = filtered,
        };
    }

    pub fn deinit(self: *Text) void {
        const allocator = CAllocator.get();
        for (self.parameters) |param_slice| {
            allocator.free(param_slice);
        }
        allocator.free(self.parameters);

        if (self.source.len > 0 and self.source.ptr != "".ptr) {
            allocator.free(self.source);
        }
        allocator.free(self.message);
        allocator.free(self.xuid);
        allocator.free(self.platform_chat_id);
        allocator.free(self.filtered);
    }
};
