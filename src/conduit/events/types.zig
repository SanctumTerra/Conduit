const Player = @import("../player/player.zig").Player;

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

pub const Event = enum {
    ServerStart,
    ServerShutdown,
    PlayerJoin,
    PlayerChat,

    pub fn DataType(comptime event: Event) type {
        return switch (event) {
            .ServerStart => ServerStartEvent,
            .ServerShutdown => ServerShutdownEvent,
            .PlayerJoin => PlayerJoinEvent,
            .PlayerChat => PlayerChatEvent,
        };
    }
};
