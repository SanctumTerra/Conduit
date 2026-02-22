const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const PlayerListAction = @import("../enums/player-list-action.zig").PlayerListAction;
const PlayerListEntry = @import("../types/player-list-entry.zig").PlayerListEntry;

pub const PlayerListPacket = struct {
    action: PlayerListAction,
    entries: []const PlayerListEntry,

    pub fn serialize(self: *PlayerListPacket, stream: *BinaryStream, allocator: std.mem.Allocator) ![]const u8 {
        try stream.writeVarInt(Packet.PlayerList);
        try stream.writeUint8(@intFromEnum(self.action));
        try stream.writeVarInt(@intCast(self.entries.len));

        switch (self.action) {
            .Add => {
                for (self.entries) |entry| {
                    try PlayerListEntry.writeAdd(stream, entry, allocator);
                }
                for (self.entries) |_| {
                    try stream.writeBool(true);
                }
            },
            .Remove => {
                for (self.entries) |entry| {
                    try PlayerListEntry.writeRemove(stream, entry);
                }
            },
        }

        return stream.getBuffer();
    }
};
