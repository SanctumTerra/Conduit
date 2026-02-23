const std = @import("std");
const Raknet = @import("Raknet");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const LoginData = Protocol.Login.Decoder.LoginData;
pub const NetworkHandler = @import("../network/network-handler.zig").NetworkHandler;
const Dimension = @import("../world/dimension/dimension.zig").Dimension;
const Entity = @import("../entity/entity.zig").Entity;
const EntityType = @import("../entity/entity-type.zig").EntityType;
const ItemStack = @import("../items/item-stack.zig").ItemStack;
const Container = @import("../container/container.zig").Container;

const InventoryTrait = @import("../entity/traits/inventory.zig").InventoryTrait;

pub const Player = struct {
    entity: Entity,
    connection: *Raknet.Connection,
    network: *NetworkHandler,
    loginData: LoginData,

    xuid: []const u8,
    username: []const u8,
    uuid: []const u8,

    view_distance: i32 = 8,
    sent_chunks: std.AutoHashMap(i64, void),
    spawned: bool = false,
    opened_container: ?*Container = null,

    pub fn init(
        self: *Player,
        allocator: std.mem.Allocator,
        connection: *Raknet.Connection,
        network: *NetworkHandler,
        loginData: LoginData,
        runtimeId: i64,
        entity_type: *const EntityType,
    ) !void {
        self.* = .{
            .entity = Entity.init(allocator, entity_type, runtimeId, null),
            .connection = connection,
            .network = network,
            .loginData = loginData,
            .xuid = loginData.identity_data.xuid,
            .username = loginData.identity_data.display_name,
            .uuid = loginData.identity_data.identity,
            .sent_chunks = std.AutoHashMap(i64, void).init(allocator),
        };

        self.entity.flags.setFlag(.HasGravity, true);
        self.entity.flags.setFlag(.Breathing, true);
        self.entity.flags.setFlag(.ShowName, true);
        self.entity.flags.setFlag(.AlwaysShowName, true);
        self.entity.attributes.registerWithCurrent(.Movement, 0, 3.4028235e+38, 0.1, 0.1) catch {};
        self.entity.attributes.registerWithCurrent(.UnderwaterMovement, 0, 3.4028235e+38, 0.02, 0.02) catch {};
        self.entity.attributes.registerWithCurrent(.LavaMovement, 0, 3.4028235e+38, 0.02, 0.02) catch {};

        const inv = try InventoryTrait.create(allocator, .{
            .container = undefined,
            .selected_slot = 0,
            .opened = false,
        });
        try self.entity.addTrait(inv);
    }

    pub fn deinit(self: *Player) void {
        self.sent_chunks.deinit();
        self.loginData.deinit();
        self.entity.deinit();
    }

    pub fn disconnect(self: *Player) !void {
        self.network.conduit.removePlayer(self);
        self.deinit();
        self.entity.allocator.destroy(self);
    }

    pub fn onSpawn(self: *Player) !void {
        self.sendSpawnChunks() catch |err| {
            Raknet.Logger.ERROR("Failed to send spawn chunks for {s}: {any}", .{ self.username, err });
        };
        Raknet.Logger.INFO("Player {s} has spawned.", .{self.username});

        if (self.entity.getTraitState(InventoryTrait)) |state| {
            var s: *InventoryTrait.TraitState = state;

            const item = ItemStack.fromIdentifier(
                "minecraft:diamond_shovel",
                .{},
            ) orelse return;

            s.container.setItem(0, item);
            s.container.update();
        }

        // {

        //     var str = BinaryStream.init(self.entity.allocator, null, null);
        //     defer str.deinit();

        //     const packet = Protocol.InventorySlotPacket{
        //         .containerId = .Inventory,
        //         .fullContainerName = .{
        //             .identifier = .AnvilInput,
        //             .dynamicIdentifier = 0,
        //         },
        //         .item = item.toNetworkStack(),
        //         .storageItem = .{
        //             .network = 0,
        //             .extras = null,
        //             .itemStackId = null,
        //             .metadata = null,
        //             .networkBlockId = null,
        //             .stackSize = null,
        //         },
        //         .slot = 0,
        //     };
        //     const serialized = try packet.serialize(&str);
        //     try self.network.sendPacket(self.connection, serialized);
        // }
    }

    pub fn broadcastActorFlags(self: *Player) !void {
        var str = BinaryStream.init(self.entity.allocator, null, null);
        defer str.deinit();

        const data = try self.entity.flags.buildDataItems(self.entity.allocator);
        var packet = Protocol.SetActorDataPacket.init(self.entity.allocator, self.entity.runtime_id, 0, data);
        defer packet.deinit();
        const serialized = try packet.serialize(&str);

        const snapshots = self.network.conduit.getPlayerSnapshots();
        for (snapshots) |other| {
            if (!other.spawned) continue;
            try self.network.sendPacket(other.connection, serialized);
        }
    }

    fn sendSpawnChunks(self: *Player) !void {
        const allocator = self.entity.allocator;
        const world = self.network.conduit.getWorld("world") orelse return;
        const overworld = world.getDimension("overworld") orelse return;

        const radius = self.view_distance;
        const batch_size: usize = 10;

        var packet_batch = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        defer {
            for (packet_batch.items) |pkt| allocator.free(pkt);
            packet_batch.deinit(allocator);
        }

        var cx: i32 = -radius;
        while (cx <= radius) : (cx += 1) {
            var cz: i32 = -radius;
            while (cz <= radius) : (cz += 1) {
                if (cx * cx + cz * cz > radius * radius) continue;

                const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = cx, .z = cz });
                if (self.sent_chunks.contains(chunk_hash)) continue;

                const chunk = try overworld.getOrCreateChunk(cx, cz);

                var chunk_stream = BinaryStream.init(allocator, null, null);
                defer chunk_stream.deinit();
                try chunk.serialize(&chunk_stream);
                const chunk_data = chunk_stream.getBuffer();

                var pkt_stream = BinaryStream.init(allocator, null, null);
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
                try packet_batch.append(allocator, try allocator.dupe(u8, serialized));
                try self.sent_chunks.put(chunk_hash, {});

                if (packet_batch.items.len >= batch_size) {
                    try self.network.sendPackets(self.connection, packet_batch.items);
                    for (packet_batch.items) |pkt| allocator.free(pkt);
                    packet_batch.clearRetainingCapacity();
                }
            }
        }

        if (packet_batch.items.len > 0) {
            try self.network.sendPackets(self.connection, packet_batch.items);
        }

        var pub_stream = BinaryStream.init(allocator, null, null);
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
