const std = @import("std");
const Protocol = @import("protocol");
const Player = @import("../player/player.zig").Player;
const BlockPermutation = @import("../world/block/block-permutation.zig").BlockPermutation;
const Entity = @import("../entity/entity.zig").Entity;

pub const ItemDrop = struct {
    identifier: []const u8,
    count: u16 = 1,
};

pub const ServerStartEvent = struct {};
pub const ServerShutdownEvent = struct {};

pub const PlayerJoinEvent = struct {
    player: *Player,
};
// TODO
pub const PlayerDisconnectEvent = struct {
    player: *Player,
};

pub const PlayerChatEvent = struct {
    player: *Player,
    message: []const u8,
};

pub const BlockPlaceEvent = struct {
    player: *Player,
    position: Protocol.BlockPosition,
    permutation: *BlockPermutation,
};

pub const BlockBreakEvent = struct {
    player: *Player,
    position: Protocol.BlockPosition,
    permutation: *BlockPermutation,
    drops: ?[]const ItemDrop = null,
    /// Item entities spawned after the block break
    entities: ?[]*Entity = null,

    pub fn getDrops(self: *const BlockBreakEvent) []const ItemDrop {
        return self.drops orelse &[_]ItemDrop{};
    }

    pub fn setDrops(self: *BlockBreakEvent, drops: []const ItemDrop) void {
        self.drops = drops;
    }
};

pub const Event = enum {
    ServerStart,
    ServerShutdown,
    PlayerJoin,
    PlayerChat,
    BlockPlace,
    BlockBreak,

    pub fn DataType(comptime event: Event) type {
        return switch (event) {
            .ServerStart => ServerStartEvent,
            .ServerShutdown => ServerShutdownEvent,
            .PlayerJoin => PlayerJoinEvent,
            .PlayerChat => PlayerChatEvent,
            .BlockPlace => BlockPlaceEvent,
            .BlockBreak => BlockBreakEvent,
        };
    }
};
