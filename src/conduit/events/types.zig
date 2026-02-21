pub const ServerStartEvent = struct {};
pub const ServerShutdownEvent = struct {};
pub const PlayerJoinEvent = struct {};

pub const Event = enum {
    ServerStart,
    ServerShutdown,
    PlayerJoin,

    pub fn DataType(comptime event: Event) type {
        return switch (event) {
            .ServerStart => ServerStartEvent,
            .ServerShutdown => ServerShutdownEvent,
            .PlayerJoin => PlayerJoinEvent,
        };
    }
};
