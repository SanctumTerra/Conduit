const std = @import("std");
const Logger = @import("Logger").Logger;
const Connection = @import("../../raknet/Connection.zig").Connection;
const Server = @import("../Server.zig").Server;

pub const Player = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    server: *Server,
    last_ping: i64,
    should_remove: bool,
    // Add other player-specific fields here

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, server: *Server) !Player {
        var player = Player{
            .allocator = allocator,
            .connection = connection,
            .server = server,
            .last_ping = std.time.milliTimestamp(),
            .should_remove = false,
        };
        player.connection.setGamePacketCallback(game_packet_callback, &player);
        return player;
    }

    pub fn handleGamePacket(self: *Player, data: []const u8) void {
        _ = self;
        // const ID = data[0];
        Logger.INFO("Received game packet: {any}", .{data});
    }

    fn game_packet_callback(data: []const u8, context: ?*anyopaque) void {
        const player = @as(*Player, @ptrCast(@alignCast(context)));
        player.handleGamePacket(data);
    }

    pub fn deinit(self: *const Player) void {
        _ = self;
        // Cleanup player resources
        Logger.DEBUG("Player deinitializing", .{});
        // Add any cleanup logic here
    }

    pub fn tick(self: *Player) void {
        // Update player state, check for timeouts, etc.
        const current_time = std.time.milliTimestamp();

        // Check for timeout (e.g., 30 seconds)
        if (current_time - self.last_ping > 30000) {
            Logger.WARN("Player timed out", .{});
            self.should_remove = true;
            return;
        }

        // Add other per-tick player logic here
    }

    pub fn shouldRemove(self: *Player) bool {
        return self.should_remove or !self.connection.isConnected();
    }

    pub fn send(self: *Player, data: []const u8) !void {
        try self.connection.send(data);
    }
};
