const Logger = @import("Logger").Logger;
const RaknetServer = @import("../raknet/Server.zig").Server;
const Connection = @import("../raknet/Connection.zig").Connection;
const std = @import("std");
const Player = @import("./player/Player.zig").Player;
const NetworkHandler = @import("./player/NetworkHandler.zig").NetworkHandler;

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

        self.tick_thread = try std.Thread.spawn(.{}, tickLoop, .{self});
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
        server.handleDisconnectionByAddress(address);
    }

    fn handleConnection(self: *Server, connection: *Connection) !void {
        const key = connection.key;
        const new_player = try Player.init(self.allocator, connection, self);
        try self.players.put(key, new_player);
        const player_ptr = self.players.getPtr(key).?;
        player_ptr.network_handler = NetworkHandler.init(player_ptr);
        player_ptr.connection.setGamePacketCallback(Player.game_packet_callback, player_ptr);
        Logger.INFO("Player {s} connected", .{key});
    }

    fn handleDisconnection(self: *Server, connection: *Connection) void {
        const key = connection.key;
        if (self.players.fetchRemove(key)) |const_entry| {
            var player_to_deinit = const_entry.value;
            player_to_deinit.deinit();
            Logger.INFO("Player {s} disconnected", .{key});
        }
    }

    fn handleDisconnectionByAddress(self: *Server, address: std.net.Address) void {
        var buf: [48]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{any}", .{address}) catch |err| {
            Logger.ERROR("Failed to format address: {s}", .{@errorName(err)});
            return;
        };
        if (self.players.fetchRemove(key)) |const_entry| {
            var player_to_deinit = const_entry.value;
            player_to_deinit.deinit();
            Logger.INFO("Player {s} disconnected", .{key});
        }
    }

    fn tick(self: *Server) void {
        var iterator = self.players.iterator();
        var players_to_disconnect = std.ArrayList([]const u8).init(self.allocator);
        defer players_to_disconnect.deinit();

        while (iterator.next()) |entry| {
            const player = entry.value_ptr;
            player.tick();
            if (player.shouldRemove()) {
                players_to_disconnect.append(entry.key_ptr.*) catch |err| {
                    Logger.ERROR("Failed to add player key {s} to disconnect list: {}", .{ entry.key_ptr.*, err });
                };
            }
        }

        for (players_to_disconnect.items) |player_key_to_disconnect| {
            if (self.players.getPtr(player_key_to_disconnect)) |player_to_disconnect| {
                Logger.INFO("Player {s} marked for removal, initiating RakNet disconnect.", .{player_key_to_disconnect});
                self.raknet.disconnectClient(player_to_disconnect.connection.address, player_to_disconnect.connection.key);
            } else {
                Logger.WARN("Player {s} was marked for removal but not found in map for RakNet disconnect.", .{player_key_to_disconnect});
            }
        }
    }

    pub fn broadcastPacket(self: *Server, packet: []const u8) void {
        var iterator = self.players.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.sendPacket(packet) catch |err| {
                Logger.ERROR("Failed to send packet to player {s}: {}", .{ entry.key_ptr.*, err });
            };
        }
    }
};
