const std = @import("std");
const Logger = @import("Logger").Logger;
const Connection = @import("../../raknet/Connection.zig").Connection;
const Server = @import("../Server.zig").Server;
const NetworkHandler = @import("NetworkHandler.zig").NetworkHandler;
const Framer = @import("../../protocol/misc/Framer.zig").Framer;
const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const CompressionMethod = @import("NetworkHandler.zig").CompressionMethod;
const IdentityData = @import("data/IdentityData.zig").IdentityData;
const ClientData = @import("data/ClientData.zig").ClientData;

pub const Player = struct {
    network_handler: ?NetworkHandler,
    allocator: std.mem.Allocator,
    connection: *Connection,
    server: *Server,
    last_packet: i64,
    should_remove: bool,
    identity_data: IdentityData,
    client_data: ClientData,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, server: *Server) !Player {
        var player = Player{
            .allocator = allocator,
            .connection = connection,
            .server = server,
            .last_packet = std.time.milliTimestamp(),
            .should_remove = false,
            .identity_data = IdentityData.init(allocator),
            .client_data = ClientData.init(allocator),
            .network_handler = null,
        };
        player.network_handler = NetworkHandler.init(&player);
        player.connection.setGamePacketCallback(game_packet_callback, &player);
        return player;
    }

    pub fn handleGamePacket(self: *Player, data: []const u8) void {
        _ = self;
        Logger.INFO("Received game packet: {any}", .{data});
    }

    pub fn game_packet_callback(data: []const u8, context: ?*anyopaque) void {
        const player = @as(*Player, @ptrCast(@alignCast(context)));
        if (player.network_handler) |*handler| {
            handler.handleGamePacket(data);
        }
    }

    pub fn deinit(self: *Player) void {
        self.client_data.deinit();
        self.identity_data.deinit();
        Logger.DEBUG("Player deinitializing", .{});
    }

    pub fn tick(self: *Player) void {
        const current_time = std.time.milliTimestamp();

        if (current_time - self.last_packet > 30000) {
            Logger.WARN("Player timed out", .{});
            self.should_remove = true;
            return;
        }
    }

    pub fn shouldRemove(self: *Player) bool {
        return self.should_remove or !self.connection.is_active.load(.acquire);
    }

    pub fn send(self: *Player, data: []const u8) !void {
        try self.connection.send(data);
    }

    pub fn sendPacket(self: *Player, packet: []const u8) !void {
        var frames = [_][]const u8{packet};
        const framed = Framer.frame(&frames);
        defer self.allocator.free(framed);

        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeUint8(0xFE);

        if (self.network_handler) |nh| {
            if (nh.compression and framed.len >= nh.compressionThreshold) {
                stream.writeUint8(@intFromEnum(CompressionMethod.Zlib));

                var compressed_data = std.ArrayList(u8).init(self.allocator);
                defer compressed_data.deinit();

                var compressor = try std.compress.flate.compressor(compressed_data.writer(), .{});
                try compressor.writer().writeAll(framed);
                try compressor.finish();

                stream.write(compressed_data.items);
                Logger.DEBUG("Compressed packet: {d} -> {d} bytes", .{ framed.len, compressed_data.items.len });
            } else {
                stream.write(framed);
            }
        } else {
            stream.write(framed);
        }

        const final_packet = try stream.toOwnedSlice();

        const frame = self.connection.frameIn(final_packet);
        self.connection.sendFrame(frame, 0);
        defer self.allocator.free(final_packet);
    }
};
