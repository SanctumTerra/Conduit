const Protocol = @import("protocol");
const Player = @import("../player/player.zig").Player;
const BlockPermutation = @import("../world/block/block-permutation.zig").BlockPermutation;

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
