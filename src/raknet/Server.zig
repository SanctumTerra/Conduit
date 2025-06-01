const std = @import("std");
const Socket = @import("./socket/socket.zig").Socket;
const Logger = @import("Logger").Logger;
const Callocator = @import("CAllocator");
const Packets = @import("./proto/Packets.zig").Packets;
const UnconnectedPing = @import("./proto/offline/UnconnectedPing.zig").UnconnectedPing;
const UnconnectedPong = @import("./proto/offline/UnconnectedPong.zig").UnconnectedPong;
const Advertisement = @import("./proto/Advertisement.zig").Advertisement;

const ServerConfig = struct {
    const Self = @This();
    address: []const u8 = "0.0.0.0",
    port: u16 = 19132,
    max_connections: u16 = 100,
    advertisement: Advertisement = Advertisement.init(
        .MCPE,
        "Conduit Server",
        800,
        "1.21.80",
        0,
        10,
        0,
        "Conduit Server",
        "Survival",
    ),

    pub fn deinit(self: *ServerConfig) void {
        self.address = "";
        self.port = 0;
        self.max_connections = 0;
    }
};

pub const Server = struct {
    const Self = @This();
    config: ServerConfig,
    socket: ?Socket,
    allocator: std.mem.Allocator,
    // var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
    // const random_guid = prng.random().int(i64);
    pub fn init(config: ServerConfig) !Self {
        return Self{ .config = config, .socket = null, .allocator = Callocator.get() };
    }

    pub fn deinit(self: *Self) void {
        self.config.deinit();
        if (self.socket) |socket| {
            socket.deinit();
        }
    }

    pub fn listen(self: *Self) void {
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
        self.config.advertisement.guid = prng.random().int(i64);
        self.socket = Socket.init(self.allocator, self.config.address, self.config.port) catch |err| {
            Logger.ERROR("Failed to create socket: {}", .{err});
            return;
        };

        self.socket.?.listen() catch |err| {
            Logger.ERROR("Failed to listen: {}", .{err});
            return;
        };

        self.socket.?.setCallback(callback, self);
    }

    pub fn callback(data: []const u8, from_addr: std.net.Address, context: ?*anyopaque) void {
        const server = @as(*Self, @ptrCast(@alignCast(context)));
        defer {
            // Log data length
            Callocator.get().free(data);
            Logger.INFO("| {any} | ", .{data.len});
        }

        server.handlePacket(data, from_addr);
    }

    pub fn handlePacket(self: *Self, data: []const u8, from_addr: std.net.Address) void {
        const ID = data[0];

        switch (ID) {
            Packets.UnconnectedPing => {
                // NOTE! We do not need to handle Pings, as they provide no necessary information.
                const string = self.config.advertisement.toString();
                var pong = UnconnectedPong.init(
                    std.time.milliTimestamp(),
                    self.config.advertisement.guid,
                    string,
                );
                const pong_data = pong.serialize();
                self.send(pong_data, from_addr);
                Callocator.get().free(string);
                defer Callocator.get().free(pong_data);
            },
            0x0e => {
                // Skip, test packet
            },
            else => {
                Logger.WARN("Unknown packet ID: {}", .{ID});
            },
        }
    }

    pub fn send(self: *Self, data: []const u8, to_addr: std.net.Address) void {
        if (self.socket == null) {
            Logger.ERROR("Socket is not initialized", .{});
            return;
        }

        self.socket.?.send(data, to_addr) catch |err| {
            Logger.ERROR("Failed to send: {}", .{err});
            return;
        };
    }
};
