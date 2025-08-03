pub const Player = struct {
    const Self = @This();
    connection: *Connection,
    server: *Server,
    networkHandler: NetworkHandler,

    // Player identity information
    username: ?[]const u8 = null,
    xuid: ?[]const u8 = null,
    allocator: std.mem.Allocator,
    entityId: i64,
    runtimeId: u64,

    pub fn init(connection: *Connection, server: *Server) !Self {
        server.lastEntityId += 1;
        var self = Self{
            .connection = connection,
            .server = server,
            .networkHandler = undefined, // We'll set this next
            .username = null,
            .xuid = null,
            .entityId = server.lastEntityId,
            .runtimeId = @as(u64, @intCast(server.lastEntityId)),
            .allocator = CAllocator.get(),
        };
        self.networkHandler = try NetworkHandler.init();
        return self;
    }

    pub fn setPlayerInfo(self: *Self, username: ?[]const u8, xuid: ?[]const u8) !void {
        // Free existing data if any
        if (self.username) |old_username| {
            self.allocator.free(old_username);
        }
        if (self.xuid) |old_xuid| {
            self.allocator.free(old_xuid);
        }

        // Set new data
        if (username) |name| {
            self.username = try self.allocator.dupe(u8, name);
        } else {
            self.username = null;
        }

        if (xuid) |id| {
            self.xuid = try self.allocator.dupe(u8, id);
        } else {
            self.xuid = null;
        }

        Logger.INFO("Player info set - Username: {?s}, XUID: {?s}", .{ self.username, self.xuid });
    }

    pub fn getPlayerInfo(self: *const Self) struct { username: ?[]const u8, xuid: ?[]const u8 } {
        return .{ .username = self.username, .xuid = self.xuid };
    }

    pub fn deinit(self: *Self) void {
        if (self.username) |username| {
            self.allocator.free(username);
        }
        if (self.xuid) |xuid| {
            self.allocator.free(xuid);
        }
    }

    pub fn onGamePacket(connection: *Connection, data: []const u8, context: ?*anyopaque) void {
        _ = connection;
        const player = @as(*Player, @ptrCast(@alignCast(context)));
        player.networkHandler.handle(player, data);

        // if (player.network_handler) |*handler| {
        //     handler.handleGamePacket(data);
        // }
    }

    pub fn sendPacket(self: *Player, packet: []const u8) !void {
        var frames = [_][]const u8{packet};
        const framed = Framer.frame(&frames);
        defer CAllocator.get().free(framed);

        var buffer = std.ArrayList(u8).init(CAllocator.get());
        try buffer.append(0xFE);
        defer buffer.deinit();

        // Check if compression is enabled and if packet meets threshold
        const compression_method = if (self.networkHandler.compression_enabled and
            framed.len >= self.networkHandler.compression_threshold)
            self.networkHandler.compression_method
        else
            CompressionMethod.NotPresent;

        const compressed = try NetworkHandler.compressPacket(framed, compression_method);
        try buffer.appendSlice(compressed);
        defer CAllocator.get().free(compressed);

        const frame = Connection.frameIn(buffer.items, CAllocator.get());
        self.connection.sendFrame(frame, .Immediate);
    }
};

const std = @import("std");
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const Server = @import("../Server.zig").Server;
const Connection = @import("ZigNet").Connection;
const NetworkHandler = @import("./NetworkHandler.zig").NetworkHandler;
const Framer = @import("../../protocol/misc/Framer.zig").Framer;
const CompressionMethod = @import("../../protocol/enums/CompressionMethod.zig").CompressionMethod;
