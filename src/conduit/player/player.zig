const std = @import("std");
const Raknet = @import("Raknet");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const LoginData = Protocol.Login.Decoder.LoginData;
pub const NetworkHandler = @import("../network/network-handler.zig").NetworkHandler;
const Dimension = @import("../world/dimension/dimension.zig").Dimension;
const EntityActorFlags = @import("../entity/root.zig").EntityActorFlags;

pub const Player = struct {
    allocator: std.mem.Allocator,
    connection: *Raknet.Connection,
    network: *NetworkHandler,
    loginData: LoginData,
    runtimeId: i64,

    xuid: []const u8,
    username: []const u8,
    uuid: []const u8,
    flags: EntityActorFlags,

    view_distance: i32 = 8,
    sent_chunks: std.AutoHashMap(i64, void),

    pub fn init(
        allocator: std.mem.Allocator,
        connection: *Raknet.Connection,
        network: *NetworkHandler,
        loginData: LoginData,
        runtimeId: i64,
    ) !Player {
        var player = Player{
            .allocator = allocator,
            .connection = connection,
            .network = network,
            .loginData = loginData,
            .runtimeId = runtimeId,
            .xuid = loginData.identity_data.xuid,
            .username = loginData.identity_data.display_name,
            .uuid = loginData.identity_data.identity,
            .sent_chunks = std.AutoHashMap(i64, void).init(allocator),
            .flags = undefined,
        };
        player.flags = EntityActorFlags.init(&player);

        player.flags.setFlag(.HasGravity, true);
        player.flags.setFlag(.Breathing, true);
        return player;
    }

    pub fn deinit(self: *Player) void {
        self.sent_chunks.deinit();
        self.loginData.deinit();
    }

    pub fn disconnect(self: *Player) !void {
        if (self.network.conduit.players.fetchRemove(self.runtimeId)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }

    pub fn onSpawn(self: *Player) void {
        self.sendSpawnChunks() catch |err| {
            Raknet.Logger.ERROR("Failed to send spawn chunks for {s}: {any}", .{ self.username, err });
        };
        Raknet.Logger.INFO("Player {s} has spawned.", .{self.username});
    }

    fn sendSpawnChunks(self: *Player) !void {
        const world = self.network.conduit.getWorld("world") orelse return;
        const overworld = world.getDimension("overworld") orelse return;

        const radius = self.view_distance;
        const batch_size: usize = 10;

        var packet_batch = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        defer {
            for (packet_batch.items) |pkt| self.allocator.free(pkt);
            packet_batch.deinit(self.allocator);
        }

        var cx: i32 = -radius;
        while (cx <= radius) : (cx += 1) {
            var cz: i32 = -radius;
            while (cz <= radius) : (cz += 1) {
                if (cx * cx + cz * cz > radius * radius) continue;

                const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = cx, .z = cz });
                if (self.sent_chunks.contains(chunk_hash)) continue;

                const chunk = try overworld.getOrCreateChunk(cx, cz);

                var chunk_stream = BinaryStream.init(self.allocator, null, null);
                defer chunk_stream.deinit();
                try chunk.serialize(&chunk_stream);
                const chunk_data = chunk_stream.getBuffer();

                var pkt_stream = BinaryStream.init(self.allocator, null, null);
                defer pkt_stream.deinit();

                var level_chunk = Protocol.LevelChunkPacket{
                    .x = cx,
                    .z = cz,
                    .dimension = .Overworld,
                    .highestSubChunkCount = 0,
                    .subChunkCount = @intCast(chunk.getSubChunkSendCount()),
                    .cacheEnabled = false,
                    .blobs = &[_]u64{},
                    .data = chunk_data,
                };

                const serialized = try level_chunk.serialize(&pkt_stream);
                try packet_batch.append(self.allocator, try self.allocator.dupe(u8, serialized));
                try self.sent_chunks.put(chunk_hash, {});

                if (packet_batch.items.len >= batch_size) {
                    try self.network.sendPackets(self.connection, packet_batch.items);
                    for (packet_batch.items) |pkt| self.allocator.free(pkt);
                    packet_batch.clearRetainingCapacity();
                }
            }
        }

        if (packet_batch.items.len > 0) {
            try self.network.sendPackets(self.connection, packet_batch.items);
        }

        var pub_stream = BinaryStream.init(self.allocator, null, null);
        defer pub_stream.deinit();

        var update = Protocol.NetworkChunkPublisherUpdatePacket{
            .coordinate = Protocol.BlockPosition{ .x = 0, .y = 100, .z = 0 },
            .radius = @intCast(radius * 16),
            .savedChunks = &[_]Protocol.ChunkCoords{},
        };
        const pub_serialized = try update.serialize(&pub_stream);
        try self.network.sendPacket(self.connection, pub_serialized);
    }
};
