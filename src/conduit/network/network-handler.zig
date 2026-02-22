const std = @import("std");
const Raknet = @import("Raknet");
const BinaryStream = @import("BinaryStream").BinaryStream;
const protocol = @import("protocol");
const Packet = protocol.Packet;

const Conduit = @import("../conduit.zig").Conduit;
const Compression = @import("./compression/root.zig").Compression;
const CompressionOptions = @import("./compression/options.zig").CompressionOptions;

const handleNetworkSettings = @import("./handlers/request-network-settings.zig").handleNetworkSettings;
const handleLogin = @import("./handlers/login.zig").handleLogin;
const handleResourcePack = @import("./handlers/resource-packs-response.zig").handleResourcePack;
const handleTextPacket = @import("./handlers/text.zig").handleTextPacket;
const handleRequestChunkRadius = @import("./handlers/request-chunk-radius.zig").handleRequestChunkRadius;
const handleSetLocalPlayerAsInitialized = @import("./handlers/set-local-player-as-initialized.zig").handleSetLocalPlayerAsInitialized;
const handlePlayerAuthInput = @import("./handlers/player-auth-input.zig").handlePlayerAuthInput;
const handleAnimate = @import("./handlers/animate.zig").handleAnimate;

pub const NetworkHandler = struct {
    conduit: *Conduit,
    allocator: std.mem.Allocator,
    options: CompressionOptions,
    lastRuntimeId: i64 = 0,

    pub fn init(c: *Conduit) !*NetworkHandler {
        const self = try c.allocator.create(NetworkHandler);
        self.* = .{
            .conduit = c,
            .allocator = c.allocator,
            .options = .{
                .compressionMethod = protocol.CompressionMethod.Zlib,
                .compressionThreshold = 255,
            },
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

    pub fn onGamePacket(self: *NetworkHandler, conn: *Raknet.Connection, payload: []const u8) !void {
        const decompressed = try Compression.decompress(payload, self.options, self.allocator);
        defer decompressed.deinit();

        for (decompressed.packets) |packet| {
            if (packet.len == 0) continue;

            var stream = BinaryStream.init(self.allocator, packet, null);
            defer stream.deinit();

            const id = stream.readVarInt() catch continue;
            stream.offset = 0;

            switch (id) {
                Packet.RequestNetworkSettings => handleNetworkSettings(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("RequestNetworkSettings error: {any}", .{err});
                },
                Packet.Login => handleLogin(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("LoginPacket error: {any}", .{err});
                },
                Packet.ResourcePackResponse => handleResourcePack(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("ResourcePackResponse error: {any}", .{err});
                },
                Packet.Text => handleTextPacket(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("Text error: {any}", .{err});
                },
                Packet.RequestChunkRadius => handleRequestChunkRadius(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("RequestChunkRadius error: {any}", .{err});
                },
                Packet.SetLocalPlayerAsInitialized => handleSetLocalPlayerAsInitialized(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("SetLocalPlayerAsInitialized error: {any}", .{err});
                },
                Packet.PlayerAuthInput => handlePlayerAuthInput(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("PlayerAuthInput error: {any}", .{err});
                },
                Packet.Animate => handleAnimate(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("Animate error: {any}", .{err});
                },
                else => Raknet.Logger.INFO("Unhandled packet 0x{x}", .{id}),
            }
        }
    }

    pub fn sendUncompressedPacket(self: *NetworkHandler, conn: *Raknet.Connection, packet: []const u8) !void {
        const packets = [_][]const u8{packet};
        const options = CompressionOptions{ .compressionMethod = .NotPresent, .compressionThreshold = 255 };
        const compressed = try Compression.compress(&packets, options, self.allocator);
        defer self.allocator.free(compressed);
        conn.sendReliableMessage(compressed, .Normal);
    }

    pub fn sendPacket(self: *NetworkHandler, conn: *Raknet.Connection, packet: []const u8) !void {
        const packets = [_][]const u8{packet};
        const compressed = try Compression.compress(&packets, self.options, self.allocator);
        defer self.allocator.free(compressed);
        conn.sendReliableMessage(compressed, .Normal);
    }

    pub fn sendPackets(self: *NetworkHandler, conn: *Raknet.Connection, packets: []const []const u8) !void {
        const compressed = try Compression.compress(packets, self.options, self.allocator);
        defer self.allocator.free(compressed);
        conn.sendReliableMessage(compressed, .Normal);
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.allocator.destroy(self);
    }
};
