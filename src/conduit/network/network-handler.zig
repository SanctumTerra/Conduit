const std = @import("std");
const Raknet = @import("Raknet");

const Conduit = @import("../conduit.zig").Conduit;
const Compression = @import("./compression/root.zig").Compression;

pub const NetworkHandler = struct {
    conduit: *Conduit,
    allocator: std.mem.Allocator,

    pub fn init(c: *Conduit) !*NetworkHandler {
        const self = try c.allocator.create(NetworkHandler);
        self.* = .{
            .conduit = c,
            .allocator = c.allocator,
        };

        self.conduit.*.raknet.setConnectCallback(onConnect, self);
        return self;
    }

    pub fn onConnect(connection: *Raknet.Connection, context: ?*anyopaque) void {
        const self = @as(*NetworkHandler, @ptrCast(@alignCast(context)));
        connection.setGamePacketCallback(onPacket, self);
    }

    pub fn onPacket(conn: *Raknet.Connection, payload: []const u8, context: ?*anyopaque) void {
        const self = @as(*NetworkHandler, @ptrCast(@alignCast(context)));
        self.onGamePacket(conn, payload) catch |err| {
            Raknet.Logger.ERROR("Failed to handle encapsulated {any}", .{err});
        };
    }

    pub fn onGamePacket(self: *NetworkHandler, _: *Raknet.Connection, payload: []const u8) !void {
        const decompressed = try Compression.decompress(
            payload,
            self.allocator,
        );
        defer decompressed.deinit();

        for (decompressed.packets) |packet| {
            Raknet.Logger.INFO("Received {any}", .{packet});
        }
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.allocator.destroy(self);
    }
};
