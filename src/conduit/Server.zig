const Logger = @import("Logger").Logger;
const RaknetServer = @import("../raknet/Server.zig").Server;
const Connection = @import("../raknet/Connection.zig").Connection;
const std = @import("std");
const Player = @import("./player/Player.zig").Player;

pub const ServerConfig = struct {
    address: []const u8 = "0.0.0.0",
    port: u16 = 19132,
    max_players: u16 = 60,
    tick_rate: u16 = 20, // 20 ticks per SECOND!
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    players: std.StringHashMap(Player),
    raknet: RaknetServer,
    config: ServerConfig,
    running: std.atomic.Value(bool),
    tick_thread: ?std.Thread,

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !Server {
        Logger.INFO("Server initialized", .{});

        return Server{
            .allocator = allocator,
            .players = std.StringHashMap(Player).init(allocator),
            .raknet = try RaknetServer.init(.{
                .address = config.address,
                .max_connections = config.max_players,
                .port = config.port,
            }),
            .config = config,
            .running = std.atomic.Value(bool).init(false),
            .tick_thread = null,
        };
    }

    pub fn deinit(self: *Server) void {
        self.stop();

        // Deinit all players
        var iterator = self.players.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.players.deinit();

        self.raknet.deinit();
        Logger.INFO("Server shut down", .{});
    }

    pub fn start(self: *Server) !void {
        Logger.INFO("Starting server on {s}:{}", .{ self.config.address, self.config.port });

        self.running.store(true, .seq_cst);
        self.raknet.setConnectionCallback(connection_callback, self);
        self.raknet.setDisconnectionCallback(disconnection_callback, self);

        // Start the tick thread
        self.tick_thread = try std.Thread.spawn(.{}, tickLoop, .{self});

        // Start listening for connections
        self.raknet.listen();
    }

    pub fn stop(self: *Server) void {
        if (!self.running.load(.seq_cst)) return;

        Logger.INFO("Stopping server...", .{});
        self.running.store(false, .seq_cst);

        if (self.tick_thread) |thread| {
            thread.join();
            self.tick_thread = null;
        }
    }

    fn tickLoop(self: *Server) void {
        const tick_interval_ns: u64 = @as(u64, std.time.ns_per_s) / self.config.tick_rate;

        while (self.running.load(.seq_cst)) {
            const start_time = std.time.nanoTimestamp();

            self.tick();

            // Sleep for remaining time to maintain tick rate
            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed < tick_interval_ns) {
                const sleep_duration = tick_interval_ns - @as(u64, @intCast(elapsed));
                std.time.sleep(sleep_duration);
            }
        }

        Logger.INFO("Tick thread stopped", .{});
    }

    fn connection_callback(connection: *Connection, context: ?*anyopaque) void {
        const server = @as(*Server, @ptrCast(@alignCast(context)));
        server.handleConnection(connection) catch |err| {
            Logger.ERROR("Failed to handle connection: {s}", .{@errorName(err)});
        };
    }

    fn disconnection_callback(address: std.net.Address, context: ?*anyopaque) void {
        const server = @as(*Server, @ptrCast(@alignCast(context)));
        // Since we don't have the connection object directly, we need to find it by address
        server.handleDisconnectionByAddress(address);
    }

    fn handleConnection(self: *Server, connection: *Connection) !void {
        const key = connection.key;
        const player = try Player.init(self.allocator, connection, self);
        try self.players.put(key, player);
        Logger.INFO("Player {s} connected", .{key});
    }

    fn handleDisconnection(self: *Server, connection: *Connection) void {
        const key = connection.key;
        if (self.players.fetchRemove(key)) |entry| {
            entry.value.deinit();
            Logger.INFO("Player {s} disconnected", .{key});
        }
    }

    fn handleDisconnectionByAddress(self: *Server, address: std.net.Address) void {
        // Format address to key
        var buf: [48]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{any}", .{address}) catch |err| {
            Logger.ERROR("Failed to format address: {s}", .{@errorName(err)});
            return;
        };

        // Use the key to find and remove the player
        if (self.players.fetchRemove(key)) |entry| {
            entry.value.deinit();
            Logger.INFO("Player {s} disconnected", .{key});
        }
    }

    fn tick(self: *Server) void {
        // Tick all players
        var iterator = self.players.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.tick();
        }
    }
};
