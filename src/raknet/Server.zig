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

pub const ConenctionCallBack = *const fn (connection: *Connection, context: ?*anyopaque) void;
pub const DisconnectionCallBack = *const fn (address: std.net.Address, context: ?*anyopaque) void;

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
    connection_callback: ?ConenctionCallBack = null,
    connection_context: ?*anyopaque = null,
    disconnection_callback: ?DisconnectionCallBack = null,
    disconnection_context: ?*anyopaque = null,

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
        if (self.running.load(.acquire)) {
            self.running.store(false, .release);
            if (self.maintenance_thread) |thread| {
                thread.join();
            }
        }

        self.config.deinit();
        if (self.socket) |*socket| {
            socket.deinit();
        }

        var deactivate_iter = self.connections.iterator();
        while (deactivate_iter.next()) |entry| {
            entry.value_ptr.deactivate();
        }

        var connections_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer connections_to_remove.deinit();

        var it = self.connections.iterator();
        while (it.next()) |entry| {
            connections_to_remove.append(entry.key_ptr.*) catch |err| {
                Logger.ERROR("Failed to add connection key to removal list: {}", .{err});
                continue;
            };
        }

        for (connections_to_remove.items) |key| {
            if (self.connections.getPtr(key)) |conn| {
                var conn_copy = conn.*;
                _ = self.connections.remove(key);
                conn_copy.deinit();
            }
            std.heap.page_allocator.free(key);
        }

        self.connections.deinit();
    }

    pub fn setConnectionCallback(self: *Self, callback: ConenctionCallBack, context: ?*anyopaque) void {
        self.connection_callback = callback;
        self.connection_context = context;
    }

    pub fn setDisconnectionCallback(self: *Self, callback: DisconnectionCallBack, context: ?*anyopaque) void {
        self.disconnection_callback = callback;
        self.disconnection_context = context;
    }

    fn maintenanceLoop(server: *Self) void {
        while (server.running.load(.acquire)) {
            var it = server.connections.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.tick();
            }
            std.time.sleep(std.time.ns_per_ms * 10);
        }
        Logger.INFO("Maintenance thread stopped", .{});
    }

    pub fn listen(self: *Self) void {
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
        self.config.advertisement.guid = prng.random().int(i64);
        self.socket = Socket.init(self.allocator, self.config.address, self.config.port) catch |err| {
            Logger.ERROR("Failed to create socket: {s}", .{@errorName(err)});
            return;
        };

        self.socket.?.listen() catch |err| {
            Logger.ERROR("Failed to listen: {s}", .{@errorName(err)});
            return;
        };

        self.socket.?.setCallback(packet_callback, self);
        self.running.store(true, .release);
        self.maintenance_thread = std.Thread.spawn(.{}, maintenanceLoop, .{self}) catch |err| {
            Logger.ERROR("Failed to spawn maintenance thread: {s}", .{@errorName(err)});
            return;
        };
    }

    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
    }

    pub fn packet_callback(data: []const u8, from_addr: std.net.Address, context: ?*anyopaque, allocator: std.mem.Allocator) void {
        const server = @as(*Self, @ptrCast(@alignCast(context)));
        defer allocator.free(data);
        server.handlePacket(data, from_addr);
    }

    pub fn getAddressAsKey(self: *Self, address: std.net.Address) []const u8 {
        _ = self;
        var buf: [48]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, "{any}", .{address}) catch |err| {
            Logger.ERROR("Failed to format address: {s}", .{@errorName(err)});
            return &[_]u8{};
        };

        return std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{formatted}) catch |err| {
            Logger.ERROR("Failed to allocate key: {s}", .{@errorName(err)});
            return &[_]u8{};
        };
    }

    pub fn handlePacket(self: *Self, data: []const u8, from_addr: std.net.Address) void {
        var ID: u8 = data[0];
        if (ID & 0xF0 == 0x80) ID = 0x80;
        const key = self.getAddressAsKey(from_addr);
        defer std.heap.page_allocator.free(key);

        switch (ID) {
            Packets.UnconnectedPing => {
                const string = self.config.advertisement.toString();
                defer Callocator.get().free(string);

                var pong = UnconnectedPong.init(
                    std.time.milliTimestamp(),
                    self.config.advertisement.guid,
                    string,
                );
                const pong_data = pong.serialize();
                defer Callocator.get().free(pong_data);

                self.send(pong_data, from_addr);
            },
            Packets.OpenConnectionRequest1 => {
                var reply = ConnectionReply1.init(
                    self.config.advertisement.guid,
                    false,
                    1492,
                );
                const reply_data = reply.serialize();
                defer Callocator.get().free(reply_data);
                self.send(reply_data, from_addr);
            },
            Packets.OpenConnectionRequest2 => {
                const request = ConnectionRequest2.deserialize(data);
                defer request.address.deinit(Callocator.get());
                const address = Address.init(4, "0.0.0.0", 0);

                var reply = ConnectionReply2.init(
                    self.config.advertisement.guid,
                    address,
                    request.mtu_size,
                    false,
                );
                const reply_data = reply.serialize();
                defer Callocator.get().free(reply_data);
                self.send(reply_data, from_addr);

                if (self.connections.get(key)) |_| {
                    Logger.INFO("Connection already exists", .{});
                } else {
                    const key_copy = std.heap.page_allocator.dupe(u8, key) catch |err| {
                        Logger.ERROR("Failed to copy key: {s}", .{@errorName(err)});
                        return;
                    };
                    self.connections.put(key_copy, Connection.init(from_addr, key_copy)) catch |err| {
                        Logger.ERROR("Failed to put connection: {s}", .{@errorName(err)});
                        std.heap.page_allocator.free(key_copy);
                        return;
                    };

                    if (self.connections.getPtr(key_copy)) |conn| {
                        conn.setServer(self);
                    }
                }
            },
            0x80 => {
                if (self.connections.getPtr(key)) |conn| {
                    conn.handleFrameSet(data);
                }
            },
            Packets.Ack => {
                if (self.connections.getPtr(key)) |conn| {
                    conn.handleAck(data);
                }
            },
            Packets.Nack => {
                if (self.connections.getPtr(key)) |conn| {
                    conn.handleNack(data);
                }
            },
            Packets.DisconnectNotification => {
                if (self.connections.getPtr(key)) |conn| {
                    conn.onDisconnect();
                }
            },
            0x0e => {
                // Skip, test packet
            },
            else => {
                Logger.WARN("Unknown packet ID: {d}", .{ID});
            },
        }
    }

    pub fn send(self: *Self, data: []const u8, to_addr: std.net.Address) void {
        if (self.socket == null) {
            Logger.ERROR("Socket is not initialized", .{});
            return;
        }

        self.socket.?.send(data, to_addr) catch |err| {
            Logger.ERROR("Failed to send: {s}", .{@errorName(err)});
            return;
        };
    }

    pub fn disconnectClient(self: *Self, address: std.net.Address, key: []const u8) void {
        var addr_buf: [48]u8 = undefined;
        const addr_str = std.fmt.bufPrint(&addr_buf, "{any}", .{address}) catch "unknown address";
        Logger.DEBUG("Disconnecting client: {s}", .{addr_str});

        if (self.connections.getPtr(key)) |conn| {
            conn.deactivate();

            if (self.disconnection_callback) |callback| {
                callback(address, self.disconnection_context);
            }

            var conn_copy = conn.*;
            _ = self.connections.remove(key);

            conn_copy.deinit();

            Logger.DEBUG("Connection removed and deinitialized: {s}", .{addr_str});
        }
    }
};
