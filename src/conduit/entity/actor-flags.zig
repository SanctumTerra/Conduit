const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

const Protocol = @import("protocol");
const ActorFlags = Protocol.ActorFlags;
const ActorDataId = Protocol.ActorDataId;

const Player = @import("../player/player.zig").Player;

pub const EntityActorFlags = struct {
    player: *Player,
    flags_one: i64,
    flags_two: i64,

    pub fn init(player: *Player) EntityActorFlags {
        return .{
            .player = player,
            .flags_one = 0,
            .flags_two = 0,
        };
    }

    pub fn getFlag(self: *const EntityActorFlags, flag: ActorFlags) bool {
        const index = @intFromEnum(flag);
        if (index < 64) {
            return self.flags_one & (@as(i64, 1) << @intCast(index)) != 0;
        } else {
            return self.flags_two & (@as(i64, 1) << @intCast(index - 64)) != 0;
        }
    }

    pub fn setFlag(self: *EntityActorFlags, flag: ActorFlags, value: ?bool) void {
        const v = value orelse false;
        self.setFlagRaw(flag, v);
    }

    pub fn setFlags(self: *EntityActorFlags, flags: []const struct { flag: ActorFlags, value: bool }) void {
        for (flags) |item| {
            // TODO REMOVE AFTER DEBUG
            std.log.info("[EntityActorFlags] setFlag {s} = {}", .{ @tagName(item.flag), item.value });
            self.setFlagRaw(item.flag, item.value);
        }
    }

    pub fn clearAll(self: *EntityActorFlags) void {
        self.flags_one = 0;
        self.flags_two = 0;
    }

    pub fn buildDataItems(self: *const EntityActorFlags, allocator: std.mem.Allocator) ![]Protocol.DataItem {
        const data = try allocator.alloc(Protocol.DataItem, 2);
        data[0] = Protocol.DataItem.init(ActorDataId.Flags, .Long, .{ .Long = self.flags_one });
        data[1] = Protocol.DataItem.init(ActorDataId.FlagsTwo, .Long, .{ .Long = self.flags_two });
        return data;
    }

    fn setFlagRaw(self: *EntityActorFlags, flag: ActorFlags, value: bool) void {
        const index = @intFromEnum(flag);
        if (index < 64) {
            const mask = @as(i64, 1) << @intCast(index);
            if (value) {
                self.flags_one |= mask;
            } else {
                self.flags_one &= ~mask;
            }
        } else {
            const mask = @as(i64, 1) << @intCast(index - 64);
            if (value) {
                self.flags_two |= mask;
            } else {
                self.flags_two &= ~mask;
            }
        }
    }
};
