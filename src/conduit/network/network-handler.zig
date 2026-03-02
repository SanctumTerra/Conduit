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
const handleClientCacheStatus = @import("./handlers/client-cache-status.zig").handleClientCacheStatus;
const handleInteract = @import("./handlers/interact.zig").handleInteract;
const handleMobEquipment = @import("./handlers/mob-equipment.zig").handleMobEquipment;
const handlePacketViolationWarning = @import("./handlers/packet-violation-warning.zig").handlePacketViolationWarning;
const handleContainerClose = @import("./handlers/container-close.zig").handleContainerClose;
const handleInventoryTransaction = @import("./handlers/inventory-transaction.zig").handleInventoryTransaction;
const handleItemStackRequest = @import("./handlers/item-stack-request.zig").handleItemStackRequest;
const handlePlayerAction = @import("./handlers/player-action.zig").handlePlayerAction;
const handleCommandRequest = @import("./handlers/command-request.zig").handleCommandRequest;
const handleBlockPickRequest = @import("./handlers/block-pick-request.zig").handleBlockPickRequest;

const QueuedPacket = struct {
    conn: *Raknet.Connection,
    payload: []u8,
};

pub const NetworkHandler = struct {
    conduit: *Conduit,
    allocator: std.mem.Allocator,
    options: CompressionOptions,
    packet_queue: std.ArrayList(QueuedPacket),
    packet_queue_mutex: std.Thread.Mutex,

    pub fn init(c: *Conduit) !*NetworkHandler {
        const self = try c.allocator.create(NetworkHandler);
        self.* = .{
            .conduit = c,
            .allocator = c.allocator,
            .options = .{
                .compressionMethod = protocol.CompressionMethod.Zlib,
                .compressionThreshold = 255,
            },
            .packet_queue = std.ArrayList(QueuedPacket){ .items = &.{}, .capacity = 0 },
            .packet_queue_mutex = .{},
        };
        self.conduit.*.raknet.setConnectCallback(onConnect, self);
        self.conduit.*.raknet.setDisconnectCallback(onDisconnect, self);
        return self;
    }

    pub fn onConnect(connection: *Raknet.Connection, context: ?*anyopaque) void {
        const self = @as(*NetworkHandler, @ptrCast(@alignCast(context)));
        connection.setGamePacketCallback(onPacket, self);
    }

    pub fn onDisconnect(connection: *Raknet.Connection, context: ?*anyopaque) void {
        const self = @as(*NetworkHandler, @ptrCast(@alignCast(context)));
        const player = self.conduit.getPlayerByConnection(connection) orelse return;
        Raknet.Logger.INFO("Player {s} has disconnected.", .{player.username});
        player.disconnect(null) catch |err| {
            Raknet.Logger.ERROR("Failed to disconnect player: {any}", .{err});
        };
    }

    pub fn onPacket(conn: *Raknet.Connection, payload: []const u8, context: ?*anyopaque) void {
        const self = @as(*NetworkHandler, @ptrCast(@alignCast(context)));
        const copy = self.allocator.dupe(u8, payload) catch return;
        self.packet_queue_mutex.lock();
        defer self.packet_queue_mutex.unlock();
        self.packet_queue.append(self.allocator, .{ .conn = conn, .payload = copy }) catch {
            self.allocator.free(copy);
        };
    }

    pub fn drainPackets(self: *NetworkHandler) void {
        self.packet_queue_mutex.lock();
        var queue = self.packet_queue;
        self.packet_queue = std.ArrayList(QueuedPacket){ .items = &.{}, .capacity = 0 };
        self.packet_queue_mutex.unlock();
        defer queue.deinit(self.allocator);
        for (queue.items) |entry| {
            defer self.allocator.free(entry.payload);
            self.onGamePacket(entry.conn, entry.payload) catch |err| {
                Raknet.Logger.ERROR("Failed to handle encapsulated {any}", .{err});
            };
        }
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
                Packet.ClientCacheStatus => handleClientCacheStatus(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("ClientCacheStatus error: {any}", .{err});
                },
                Packet.Interact => handleInteract(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("Interact error: {any}", .{err});
                },
                Packet.MobEquipment => handleMobEquipment(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("MobEquipment error: {any}", .{err});
                },
                Packet.ContainerClose => handleContainerClose(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("ContainerClose error: {any}", .{err});
                },
                Packet.InventoryTransaction => handleInventoryTransaction(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("InventoryTransaction error: {any}", .{err});
                },
                Packet.ItemStackRequest => handleItemStackRequest(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("ItemStackRequest error: {any}", .{err});
                },
                Packet.PlayerAction => handlePlayerAction(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("PlayerAction error: {any}", .{err});
                },
                Packet.CommandRequest => handleCommandRequest(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("CommandRequest error: {any}", .{err});
                },
                Packet.PacketViolationWarning => handlePacketViolationWarning(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("PacketViolationWarning error: {any}", .{err});
                },
                Packet.BlockPickRequest => handleBlockPickRequest(
                    self,
                    conn,
                    &stream,
                ) catch |err| {
                    Raknet.Logger.ERROR("BlockPickRequest error: {any}", .{err});
                },
                Packet.EmoteList,
                Packet.ServerboundLoadingScreenPacket,
                Packet.SetPlayerInventoryOptions,
                => {},
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

    pub fn sendImmediate(self: *NetworkHandler, conn: *Raknet.Connection, packet: []const u8) !void {
        const packets = [_][]const u8{packet};
        const compressed = try Compression.compress(&packets, self.options, self.allocator);
        defer self.allocator.free(compressed);
        conn.sendReliableMessage(compressed, .Immediate);
    }

    pub fn sendPackets(self: *NetworkHandler, conn: *Raknet.Connection, packets: []const []const u8) !void {
        const compressed = try Compression.compress(packets, self.options, self.allocator);
        defer self.allocator.free(compressed);
        conn.sendReliableMessage(compressed, .Normal);
    }

    pub fn deinit(self: *NetworkHandler) void {
        for (self.packet_queue.items) |entry| self.allocator.free(entry.payload);
        self.packet_queue.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};
