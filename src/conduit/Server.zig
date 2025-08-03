pub const Server = struct {
    players: std.AutoHashMap(i64, Player),
    options: ServerOptions,
    tick_thread: ?std.Thread,
    running: std.atomic.Value(bool),
    raknet: RaknetServer,
    lastEntityId: i64,

    pub fn init(options: ServerOptions) !Server {
        return Server{
            .players = std.AutoHashMap(i64, Player).init(CAllocator.get()),
            .options = options,
            .tick_thread = null,
            .running = std.atomic.Value(bool).init(false),
            .lastEntityId = 0,
            .raknet = try RaknetServer.init(
                .{
                    .port = options.port,
                    .address = options.address,
                    .allocator = CAllocator.get(),
                    // . = options.max_players,
                },
            ),
        };
    }

    fn tickLoop(self: *Server) void {
        const tick_interval_ns: u64 = @as(u64, std.time.ns_per_s) / self.options.tick_rate;

        while (self.running.load(.seq_cst)) {
            const start_time = std.time.nanoTimestamp();

            // self.tick(); Todo! Readd tick

            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed < tick_interval_ns) {
                const sleep_duration = tick_interval_ns - @as(u64, @intCast(elapsed));
                std.time.sleep(sleep_duration);
            }
        }

        Logger.INFO("Tick thread stopped", .{});
    }

    pub fn listen(self: *Server) !void {
        self.running.store(true, .seq_cst);
        self.tick_thread = try std.Thread.spawn(.{}, tickLoop, .{self});
        self.raknet.setConnectCallback(onConnect, self);
        self.raknet.setDisconnectCallback(onDisconnect, self);
        self.raknet.start() catch |err| {
            Logger.WARN("Failed to start server: {s}", .{@errorName(err)});
            return err;
        };
        Logger.INFO("Server listening on {s}:{d}", .{ self.options.address, self.options.port });
    }

    pub fn stop(self: *Server) !void {
        if (!self.running.load(.seq_cst)) return;
        self.running.store(false, .seq_cst);
    }

    pub fn onConnect(connection: *Connection, context: ?*anyopaque) void {
        const self = @as(*Server, @ptrCast(@alignCast(context)));
        const key = connection.guid;
        const new_player = Player.init(connection, self) catch |err| {
            Logger.WARN("Failed to create player: {s}", .{@errorName(err)});
            return;
        };
        self.players.put(key, new_player) catch |err| {
            Logger.WARN("Failed to add player to server: {s}", .{@errorName(err)});
            return;
        };
        const player_ptr = self.players.getPtr(key).?;
        player_ptr.connection.setGamePacketCallback(Player.onGamePacket, player_ptr);
        Logger.INFO("New Session from {d}", .{key});
    }

    pub fn onDisconnect(connection: *Connection, context: ?*anyopaque) void {
        const self = @as(*Server, @ptrCast(@alignCast(context)));
        const key = connection.guid;

        if (self.players.getPtr(key)) |player| {
            Logger.INFO("Player disconnected - Username: {?s}, XUID: {?s}", .{ player.username, player.xuid });
            player.deinit();
            _ = self.players.remove(key);
        }

        Logger.INFO("Session {d} disconnected", .{key});
    }

    pub fn deinit(self: *Server) void {
        self.stop() catch {};
        if (self.tick_thread) |t| t.join();
        var it = self.players.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.players.deinit();
        self.raknet.deinit();
    }
};

pub const ServerOptions = struct {
    address: []const u8 = "127.0.0.1",
    port: u16 = 19132,
    max_players: u16 = 50,
    tick_rate: u16 = 20, // 20 ticks per SECOND!
    compression_threshold: u16 = 1,
    compression_method: CompressionMethod = .Zlib,
};

const std = @import("std");
const Logger = @import("Logger").Logger;
const CAllocator = @import("CAllocator");
const Player = @import("./player/Player.zig").Player;
const RaknetServer = @import("ZigNet").Server;
const Connection = @import("ZigNet").Connection;
const CompressionMethod = @import("../protocol/enums/CompressionMethod.zig").CompressionMethod;
