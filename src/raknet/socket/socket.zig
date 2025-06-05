const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const net = std.net;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Atomic = std.atomic.Value;

pub const SocketError = error{
    WinsockInitFailed,
    SocketCreationFailed,
    BindFailed,
    SendFailed,
    AlreadyListening,
    NotListening,
    ThreadSpawnFailed,
    AddressParseError,
    SocketClosed,
} || std.mem.Allocator.Error || std.net.Address.ListenError || std.posix.SocketError || std.posix.BindError || std.posix.SendToError || error{
    FileBusy,
    Locked,
    DeadLock,
    LockedRegionLimitExceeded,
};

pub const CallbackFn = *const fn (
    data: []u8,
    from_addr: std.net.Address,
    context: ?*anyopaque,
    allocator: Allocator,
) void;

const SocketHandle = if (builtin.os.tag == .windows)
    std.os.windows.ws2_32.SOCKET
else
    posix.socket_t;

pub const Socket = struct {
    const Self = @This();
    const BUFFER_SIZE = 1500;
    const MIN_SLEEP_MS = 1;
    const MAX_SLEEP_MS = 100;
    const ERROR_THRESHOLD = 10;

    allocator: Allocator,
    bind_address: std.net.Address,
    socket_handle: SocketHandle,
    thread: ?Thread,
    callback: ?CallbackFn,
    context: ?*anyopaque,

    // Thread synchronization
    mutex: Mutex,
    should_stop: Atomic(bool),
    is_listening: Atomic(bool),

    // Error tracking for backoff
    consecutive_errors: Atomic(u32),

    // Windows-specific
    winsock_initialized: if (builtin.os.tag == .windows) bool else void,

    pub fn init(allocator: Allocator, host: []const u8, port: u16) SocketError!Self {
        const bind_address = if (std.mem.eql(u8, host, "0.0.0.0") or host.len == 0)
            std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, port)
        else
            std.net.Address.parseIp4(host, port) catch |err| {
                std.log.err("Failed to parse address {s}:{d}: {}", .{ host, port, err });
                return SocketError.AddressParseError;
            };

        var self = Self{
            .allocator = allocator,
            .bind_address = bind_address,
            .socket_handle = if (builtin.os.tag == .windows) std.os.windows.ws2_32.INVALID_SOCKET else undefined,
            .thread = null,
            .callback = null,
            .context = null,
            .mutex = Mutex{},
            .should_stop = Atomic(bool).init(false),
            .is_listening = Atomic(bool).init(false),
            .consecutive_errors = Atomic(u32).init(0),
            .winsock_initialized = if (builtin.os.tag == .windows) false else {},
        };

        try self.createSocket();
        return self;
    }

    fn createSocket(self: *Self) SocketError!void {
        if (builtin.os.tag == .windows) {
            try self.initWinsock();

            const sock = std.os.windows.ws2_32.socket(
                std.os.windows.ws2_32.AF.INET,
                std.os.windows.ws2_32.SOCK.DGRAM,
                std.os.windows.ws2_32.IPPROTO.UDP,
            );

            if (sock == std.os.windows.ws2_32.INVALID_SOCKET) {
                const err = std.os.windows.ws2_32.WSAGetLastError();
                std.log.err("Windows socket creation failed with error: {}", .{err});
                self.cleanupWinsock();
                return SocketError.SocketCreationFailed;
            }

            // Set socket to non-blocking mode
            var mode: c_ulong = 1;
            if (std.os.windows.ws2_32.ioctlsocket(
                sock,
                std.os.windows.ws2_32.FIONBIO,
                &mode,
            ) != 0) {
                _ = std.os.windows.ws2_32.closesocket(sock);
                self.cleanupWinsock();
                return SocketError.SocketCreationFailed;
            }

            self.socket_handle = sock;
        } else {
            const sock = posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0) catch |err| {
                std.log.err("Failed to create socket: {}", .{err});
                return err;
            };

            // Set socket to non-blocking mode
            const flags = posix.fcntl(sock, posix.F.GETFL, 0) catch |err| {
                _ = posix.close(sock);
                return err;
            };
            _ = posix.fcntl(sock, posix.F.SETFL, flags | std.os.O.NONBLOCK) catch |err| {
                _ = posix.close(sock);
                return err;
            };

            // Enable address reuse
            const enable: c_int = 1;
            _ = posix.setsockopt(
                sock,
                posix.SOL.SOCKET,
                posix.SO.REUSEADDR,
                std.mem.asBytes(&enable),
            ) catch {};

            self.socket_handle = sock;
        }
    }

    fn initWinsock(self: *Self) SocketError!void {
        if (builtin.os.tag != .windows) return;
        if (self.winsock_initialized) return;

        var wsadata = std.mem.zeroes(std.os.windows.ws2_32.WSADATA);
        const result = std.os.windows.ws2_32.WSAStartup(0x0202, &wsadata);
        if (result != 0) {
            std.log.err("WSAStartup failed with error: {d}", .{result});
            return SocketError.WinsockInitFailed;
        }

        self.winsock_initialized = true;
    }

    fn cleanupWinsock(self: *Self) void {
        if (builtin.os.tag != .windows) return;
        if (self.winsock_initialized) {
            _ = std.os.windows.ws2_32.WSACleanup();
            self.winsock_initialized = false;
        }
    }

    pub fn listen(self: *Self) SocketError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_listening.load(.seq_cst)) {
            return SocketError.AlreadyListening;
        }

        if (builtin.os.tag == .windows and self.socket_handle == std.os.windows.ws2_32.INVALID_SOCKET) {
            return SocketError.SocketCreationFailed;
        }

        try self.bindSocket();

        self.should_stop.store(false, .seq_cst);
        self.consecutive_errors.store(0, .seq_cst);

        self.thread = Thread.spawn(.{}, receiveLoop, .{self}) catch |err| {
            std.log.err("Failed to spawn receive thread: {}", .{err});
            return SocketError.ThreadSpawnFailed;
        };

        self.is_listening.store(true, .seq_cst);
    }

    fn bindSocket(self: *Self) SocketError!void {
        if (builtin.os.tag == .windows) {
            const sockaddr = self.bind_address.in;
            const result = std.os.windows.ws2_32.bind(
                self.socket_handle,
                @ptrCast(&sockaddr),
                @sizeOf(@TypeOf(sockaddr)),
            );

            if (result == std.os.windows.ws2_32.SOCKET_ERROR) {
                const err = std.os.windows.ws2_32.WSAGetLastError();
                std.log.err("Windows socket bind failed with error: {}", .{err});
                return SocketError.BindFailed;
            }
        } else {
            posix.bind(
                self.socket_handle,
                &self.bind_address.any,
                self.bind_address.getOsSockLen(),
            ) catch |err| {
                std.log.err("Socket bind failed: {}", .{err});
                return err;
            };
        }
    }

    pub fn stop(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.is_listening.load(.seq_cst)) return;

        self.should_stop.store(true, .seq_cst);

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        self.is_listening.store(false, .seq_cst);
        std.log.info("Socket stopped listening", .{});
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        if (builtin.os.tag == .windows) {
            if (self.socket_handle != std.os.windows.ws2_32.INVALID_SOCKET) {
                _ = std.os.windows.ws2_32.closesocket(self.socket_handle);
            }
            self.cleanupWinsock();
        } else {
            _ = posix.close(self.socket_handle);
        }
    }

    fn receiveLoop(self: *Self) void {
        var buffer: [BUFFER_SIZE]u8 = undefined;

        while (!self.should_stop.load(.seq_cst)) {
            const result = self.receivePacket(&buffer);

            switch (result) {
                .success => |packet_info| {
                    // Reset error counter on successful receive
                    self.consecutive_errors.store(0, .seq_cst);

                    if (packet_info) |info| {
                        const data_copy = self.allocator.dupe(u8, info.data) catch |err| {
                            std.log.err("Failed to copy packet data: {}", .{err});
                            continue;
                        };

                        if (self.callback) |callback| {
                            callback(data_copy, info.from_addr, self.context, self.allocator);
                        } else {
                            self.allocator.free(data_copy);
                        }
                    }
                },
                .would_block => {
                    // Normal case - no data available
                    std.time.sleep(std.time.ns_per_ms * @as(u64, MIN_SLEEP_MS));
                },
                .error_recoverable => |err| {
                    const error_count = self.consecutive_errors.fetchAdd(1, .seq_cst) + 1;
                    const sleep_ms = @min(
                        MIN_SLEEP_MS * (@as(u64, 1) << @min(error_count, 6)),
                        MAX_SLEEP_MS,
                    );

                    if (error_count <= 3) {
                        std.log.warn("Recoverable socket error ({}): {}", .{ error_count, err });
                    } else if (error_count == ERROR_THRESHOLD) {
                        std.log.err("Too many consecutive socket errors, backing off", .{});
                    }

                    std.time.sleep(std.time.ns_per_ms * @as(u64, sleep_ms));
                },
                .error_fatal => |err| {
                    std.log.err("Fatal socket error: {}", .{err});
                    break;
                },
            }
        }
    }

    const ReceiveResult = union(enum) {
        success: ?PacketInfo,
        would_block: void,
        error_recoverable: anyerror,
        error_fatal: anyerror,
    };

    const PacketInfo = struct {
        data: []const u8,
        from_addr: std.net.Address,
    };

    fn receivePacket(self: *Self, buffer: []u8) ReceiveResult {
        if (builtin.os.tag == .windows) {
            var from_addr: std.net.Ip4Address = undefined;
            var addr_len: c_int = @sizeOf(@TypeOf(from_addr));

            const result = std.os.windows.ws2_32.recvfrom(
                self.socket_handle,
                buffer.ptr,
                @intCast(buffer.len),
                0,
                @ptrCast(&from_addr),
                &addr_len,
            );

            if (result == std.os.windows.ws2_32.SOCKET_ERROR) {
                const err = std.os.windows.ws2_32.WSAGetLastError();
                return switch (err) {
                    std.os.windows.ws2_32.WinsockError.WSAEWOULDBLOCK => .would_block,
                    std.os.windows.ws2_32.WinsockError.WSAECONNRESET,
                    std.os.windows.ws2_32.WinsockError.WSAENETDOWN,
                    std.os.windows.ws2_32.WinsockError.WSAENETUNREACH,
                    std.os.windows.ws2_32.WinsockError.WSAENETRESET,
                    std.os.windows.ws2_32.WinsockError.WSAECONNABORTED,
                    std.os.windows.ws2_32.WinsockError.WSAETIMEDOUT,
                    => .{ .error_recoverable = error.NetworkError },
                    std.os.windows.ws2_32.WinsockError.WSAEBADF,
                    std.os.windows.ws2_32.WinsockError.WSAENOTSOCK,
                    => .{ .error_fatal = error.SocketClosed },
                    else => .{ .error_recoverable = error.ReceiveFailed },
                };
            }

            if (result == 0) return .{ .success = null };

            const net_addr = std.net.Address{ .in = from_addr };
            return .{
                .success = PacketInfo{
                    .data = buffer[0..@intCast(result)],
                    .from_addr = net_addr,
                },
            };
        } else {
            var from_addr: posix.sockaddr = undefined;
            var addr_len: posix.socklen_t = @sizeOf(@TypeOf(from_addr));

            const bytes_received = posix.recvfrom(
                self.socket_handle,
                buffer,
                0,
                &from_addr,
                &addr_len,
            ) catch |err| {
                return switch (err) {
                    error.WouldBlock => .would_block,
                    error.ConnectionRefused, error.NetworkSubsystemFailed => .{ .error_recoverable = err },
                    error.FileDescriptorNotASocket,
                    error.SocketNotConnected,
                    => .{ .error_fatal = err },
                    else => .{ .error_recoverable = err },
                };
            };

            if (bytes_received == 0) return .{ .success = null };

            const net_addr = std.net.Address{ .any = from_addr };
            return .{
                .success = PacketInfo{
                    .data = buffer[0..bytes_received],
                    .from_addr = net_addr,
                },
            };
        }
    }

    pub fn setCallback(self: *Self, callback: CallbackFn, context: ?*anyopaque) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.callback = callback;
        self.context = context;
    }

    pub fn send(self: *Self, data: []const u8, to_addr: std.net.Address) SocketError!void {
        if (builtin.os.tag == .windows) {
            const result = std.os.windows.ws2_32.sendto(
                self.socket_handle,
                data.ptr,
                @intCast(data.len),
                0,
                @ptrCast(&to_addr.in),
                @sizeOf(@TypeOf(to_addr.in)),
            );

            if (result == std.os.windows.ws2_32.SOCKET_ERROR) {
                const err = std.os.windows.ws2_32.WSAGetLastError();
                std.log.err("Windows sendto failed with error: {d}", .{err});
                return SocketError.SendFailed;
            }
        } else {
            _ = posix.sendto(
                self.socket_handle,
                data,
                0,
                &to_addr.any,
                to_addr.getOsSockLen(),
            ) catch |err| {
                std.log.err("sendto failed: {any}", .{err});
                return err;
            };
        }
    }

    pub fn sendTo(self: *Self, data: []const u8, host: []const u8, port: u16) SocketError!void {
        const addr = std.net.Address.parseIp4(host, port) catch |err| {
            std.log.err("Failed to parse destination address {s}:{d}: {}", .{ host, port, err });
            return SocketError.AddressParseError;
        };
        try self.send(data, addr);
    }

    pub fn getLocalAddress(self: *Self) SocketError!std.net.Address {
        if (builtin.os.tag == .windows) {
            var addr: std.os.windows.ws2_32.sockaddr_in = undefined;
            var addr_len: c_int = @sizeOf(@TypeOf(addr));

            if (std.os.windows.ws2_32.getsockname(
                self.socket_handle,
                @ptrCast(&addr),
                &addr_len,
            ) == std.os.windows.ws2_32.SOCKET_ERROR) {
                return SocketError.SocketCreationFailed;
            }

            return std.net.Address{ .in = addr };
        } else {
            var addr: posix.sockaddr = undefined;
            var addr_len: posix.socklen_t = @sizeOf(@TypeOf(addr));

            posix.getsockname(self.socket_handle, &addr, &addr_len) catch {
                return SocketError.SocketCreationFailed;
            };

            return std.net.Address{ .any = addr };
        }
    }

    pub fn isListening(self: *Self) bool {
        return self.is_listening.load(.seq_cst);
    }
};

// fn cb(
//     data: []u8,
//     from_addr: std.net.Address,
//     context: ?*anyopaque,
//     allocator: Allocator,
// ) void {
//     defer allocator.free(data); // Important: free the data when done

//     _ = context;
//     std.log.info("Received {} bytes from {}: {s}", .{ data.len, from_addr, data });
// }
