const std = @import("std");
const Socket = @import("./socket/socket.zig").Socket;
const Logger = @import("Logger").Logger;
const Callocator = @import("CAllocator");
const Packets = @import("./proto/Packets.zig").Packets;
const UnconnectedPing = @import("./proto/offline/UnconnectedPing.zig").UnconnectedPing;
const UnconnectedPong = @import("./proto/offline/UnconnectedPong.zig").UnconnectedPong;
const Address = @import("./proto/Address.zig").Address;
const Advertisement = @import("./proto/Advertisement.zig").Advertisement;
const ConnectionRequest1 = @import("./proto/offline/ConnectionRequest1.zig").ConnectionRequest1;
const ConnectionReply1 = @import("./proto/offline/ConnectionReply1.zig").ConnectionReply1;
const ConnectionRequest2 = @import("./proto/offline/ConnectionRequest2.zig").ConnectionRequest2;
const ConnectionReply2 = @import("./proto/offline/ConnectionReply2.zig").ConnectionReply2;

const Connection = @import("./Connection.zig").Connection;

pub const UDP_HEADER_SIZE: u16 = 28;
pub const MTU_SIZES = [_]u16{ 1492, 1200, 576 };
pub const MAX_MTU_SIZE: u16 = 1492;
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
    connections: std.StringHashMap(Connection),
    allocator: std.mem.Allocator,
    running: std.atomic.Value(bool),
    maintenance_thread: ?std.Thread,

    pub fn init(config: ServerConfig) !Self {
        return Self{
            .config = config,
            .socket = null,
            .allocator = Callocator.get(),
            .connections = std.StringHashMap(Connection).init(Callocator.get()),
            .running = std.atomic.Value(bool).init(false),
            .maintenance_thread = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Stop maintenance thread if running
        if (self.running.load(.acquire)) {
            self.running.store(false, .release);
            if (self.maintenance_thread) |thread| {
                thread.join();
            }
        }

        self.config.deinit();
        if (self.socket) |socket| {
            socket.deinit();
        }

        // Free all connection keys
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            // Free the key memory
            std.heap.page_allocator.free(entry.key_ptr.*);
        }
        self.connections.deinit();
    }

    fn maintenanceLoop(server: *Self) void {
        while (server.running.load(.acquire)) {
            var it = server.connections.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.tick();
            }
            std.time.sleep(std.time.ns_per_ms * 50);
        }
        Logger.INFO("Maintenance thread stopped", .{});
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
        self.running.store(true, .release);
        self.maintenance_thread = std.Thread.spawn(.{}, maintenanceLoop, .{self}) catch |err| {
            Logger.ERROR("Failed to spawn maintenance thread: {}", .{err});
            return;
        };
    }

    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
    }

    pub fn callback(data: []const u8, from_addr: std.net.Address, context: ?*anyopaque) void {
        const server = @as(*Self, @ptrCast(@alignCast(context)));
        defer {
            // Log data length
            Callocator.get().free(data);
            // Logger.INFO("| {any} | ", .{data.len});
        }
        server.handlePacket(data, from_addr);
    }

    pub fn getAddressAsKey(self: *Self, address: std.net.Address) []const u8 {
        _ = self;
        var buf: [48]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{}", .{address}) catch |err| {
            Logger.ERROR("Failed to format address: {}", .{err});
            return &[_]u8{};
        };

        return std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{formatted}) catch |err| {
            Logger.ERROR("Failed to allocate key: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn handlePacket(self: *Self, data: []const u8, from_addr: std.net.Address) void {
        var ID: u8 = data[0];
        if (ID & 0xF0 == 0x80) ID = 0x80;
        const key = self.getAddressAsKey(from_addr);
        // Logger.INFO("Key: {s}", .{key});

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
            Packets.OpenConnectionRequest1 => {
                // const request = ConnectionRequest1.deserialize(data);
                // NOTE! No need to free this, as its not allocated.
                var reply = ConnectionReply1.init(
                    self.config.advertisement.guid,
                    false,
                    1492,
                );
                const reply_data = reply.serialize();
                self.send(reply_data, from_addr);
                defer Callocator.get().free(reply_data);
            },
            Packets.OpenConnectionRequest2 => {
                const request = ConnectionRequest2.deserialize(data);
                Logger.INFO("Connection request 2: {any}", .{request});
                defer request.address.deinit(Callocator.get());
                const address = Address.init(4, "0.0.0.0", 0);
                var reply = ConnectionReply2.init(
                    self.config.advertisement.guid,
                    address,
                    1492,
                    false,
                );
                const reply_data = reply.serialize();
                self.send(reply_data, from_addr);
                defer Callocator.get().free(reply_data);
                if (self.connections.get(key)) |_| {
                    Logger.INFO("Connection already exists", .{});
                } else {
                    Logger.INFO("Creating new connection", .{});
                    // Make a copy of the key before storing it in the hash map
                    const key_copy = std.heap.page_allocator.dupe(u8, key) catch |err| {
                        Logger.ERROR("Failed to copy key: {}", .{err});
                        return;
                    };
                    self.connections.put(key_copy, Connection.init(from_addr)) catch |err| {
                        Logger.ERROR("Failed to put connection: {}", .{err});
                        std.heap.page_allocator.free(key_copy);
                    };
                }
            },
            0x80 => {
                if (self.connections.getPtr(key)) |conn| {
                    conn.handleFrameSet(data);
                    Logger.INFO("Connection found", .{});
                } else {
                    Logger.INFO("Connection not found", .{});
                }
            },
            0x0e => {
                // Skip, test packet
            },
            else => {
                Logger.WARN("Unknown packet ID: {}", .{ID});
            },
        }
        defer std.heap.page_allocator.free(key);
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
