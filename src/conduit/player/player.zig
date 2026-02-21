const std = @import("std");
const Raknet = @import("Raknet");

pub const Player = struct {
    connection: *Raknet.Connection,
    allocator: std.mem.Allocator,

    runtimeId: i64,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: *Raknet.Connection,
        runtimeId: i64,
    ) !void {
        return Player{
            .allocator = allocator,
            .connection = connection,
            .runtimeId = runtimeId,
        };
    }
};
