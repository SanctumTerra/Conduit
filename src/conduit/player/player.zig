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
const StatsTrait = @import("../entity/traits/stats.zig").StatsTrait;
const ChunkLoadingTrait = @import("../entity/traits/chunk-loading.zig");
const CursorTrait = @import("../entity/traits/cursor.zig").CursorTrait;
const Display = @import("../items/traits/display.zig");
const DisplayTrait = Display.DisplayTrait;

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
        entity_type: *const EntityType,
    ) !void {
        self.* = .{
            .entity = Entity.init(allocator, entity_type, null),
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

        const stats = try StatsTrait.create(allocator, .{
            .tick_count = 0,
        });
        try self.entity.addTrait(stats);

        const chunk_loading = try ChunkLoadingTrait.ChunkLoadingTrait.create(allocator, .{
            .last_chunk_x = 0,
            .last_chunk_z = 0,
            .initialized = false,
        });
        try self.entity.addTrait(chunk_loading);

        const cursor_trait = try CursorTrait.create(allocator, .{
            .container = undefined,
        });
        try self.entity.addTrait(cursor_trait);
    }

    pub fn deinit(self: *Player) void {
        self.sent_chunks.deinit();
        self.loginData.deinit();
        self.entity.deinit();
    }

    pub fn disconnect(self: *Player) !void {
        self.savePlayerData();
        self.network.conduit.tasks.cancelByOwner("chunk_streaming", self.entity.runtime_id, ChunkLoadingTrait.destroyStreamState);
        self.releaseChunks();
        self.network.conduit.removePlayer(self);
        self.deinit();
        self.entity.allocator.destroy(self);
    }

    pub fn savePlayerData(self: *Player) void {
        const world = self.network.conduit.getWorld("world") orelse return;
        world.provider.writePlayer(self.uuid, self) catch |err| {
            Raknet.Logger.ERROR("Failed to save player {s}: {any}", .{ self.username, err });
        };
    }

    pub fn loadPlayerData(self: *Player) bool {
        const world = self.network.conduit.getWorld("world") orelse return false;
        return world.provider.readPlayer(self.uuid, self) catch false;
    }

    fn releaseChunks(self: *Player) void {
        const world = self.network.conduit.getWorld("world") orelse return;
        const overworld = world.getDimension("overworld") orelse return;
        const allocator = self.entity.allocator;

        var hashes = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
        var it = self.sent_chunks.keyIterator();
        while (it.next()) |key| {
            hashes.append(allocator, key.*) catch {};
        }
        self.sent_chunks.clearAndFree();
        overworld.releaseUnrenderedChunks(hashes.items);
        hashes.deinit(allocator);
    }

    pub fn onSpawn(self: *Player) !void {
        self.sendSpawnChunks() catch |err| {
            Raknet.Logger.ERROR("Failed to send spawn chunks for {s}: {any}", .{ self.username, err });
        };
        Raknet.Logger.INFO("Player {s} has spawned.", .{self.username});

        const loaded = self.loadPlayerData();

        if (loaded) {
            if (self.entity.getTraitState(InventoryTrait)) |state| {
                var s: *InventoryTrait.TraitState = state;
                s.container.update();
            }
        }

        if (self.entity.getTraitState(InventoryTrait)) |state| {
            var s: *InventoryTrait.TraitState = state;

            var item = ItemStack.fromIdentifier(
                self.entity.allocator,
                "minecraft:diamond_shovel",
                .{},
            ) orelse return;

            const display = try DisplayTrait.create(self.entity.allocator, .{});
            try item.addTrait(display);
            try Display.setDisplayName(&item, "§r§7Custom §bDiamond Shovel");

            s.container.setItem(0, item);
            s.container.update();
        }
        if (self.entity.getTraitState(InventoryTrait)) |state| {
            var s: *InventoryTrait.TraitState = state;

            var item = ItemStack.fromIdentifier(
                self.entity.allocator,
                "minecraft:dirt",
                .{
                    .stackSize = 32,
                },
            ) orelse return;

            const display = try DisplayTrait.create(self.entity.allocator, .{});
            try item.addTrait(display);
            try Display.setDisplayName(&item, "§r§2Dirt");

            s.container.setItem(1, item);
            s.container.update();
        }

        if (self.entity.getTraitState(InventoryTrait)) |state| {
            var s: *InventoryTrait.TraitState = state;

            var item = ItemStack.fromIdentifier(
                self.entity.allocator,
                "minecraft:chest",
                .{
                    .stackSize = 32,
                },
            ) orelse return;

            const display = try DisplayTrait.create(self.entity.allocator, .{});
            try item.addTrait(display);
            try Display.setDisplayName(&item, "§r§cChest");

            s.container.setItem(2, item);
            s.container.update();
        }

        {
            const EntityTypeRegistry = @import("../entity/entity-type-registry.zig").EntityTypeRegistry;
            const GravityTrait = @import("../entity/traits/gravity.zig").GravityTrait;
            const HealthTrait = @import("../entity/traits/health.zig").HealthTrait;
            const world = self.network.conduit.getWorld("world") orelse return;
            const dimension = world.getDimension("overworld") orelse return;
            if (EntityTypeRegistry.get("minecraft:zombie")) |zombie_type| {
                const pos = self.entity.position;
                const zombie = dimension.spawnEntity(zombie_type, Protocol.Vector3f.init(pos.x + 3, pos.y, pos.z + 3)) catch return;
                const gravity = GravityTrait.create(self.entity.allocator, .{
                    .force = -0.08,
                    .falling_distance = 0,
                    .falling_ticks = 0,
                    .on_ground = false,
                }) catch return;
                zombie.addTrait(gravity) catch {};
                const health = HealthTrait.create(self.entity.allocator, .{
                    .current = 20,
                    .max = 20,
                }) catch return;
                zombie.addTrait(health) catch {};
            }
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

        const cx = @as(i32, @intFromFloat(@floor(self.entity.position.x))) >> 4;
        const cz = @as(i32, @intFromFloat(@floor(self.entity.position.z))) >> 4;
        const immediate_radius: i32 = 3;

        var packet_batch = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        defer {
            for (packet_batch.items) |pkt| allocator.free(pkt);
            packet_batch.deinit(allocator);
        }

        var ring: i32 = 0;
        while (ring <= immediate_radius) : (ring += 1) {
            var dx: i32 = -ring;
            while (dx <= ring) : (dx += 1) {
                var dz: i32 = -ring;
                while (dz <= ring) : (dz += 1) {
                    if (ring > 0 and @abs(dx) != ring and @abs(dz) != ring) continue;
                    if (dx * dx + dz * dz > immediate_radius * immediate_radius) continue;

                    const chunk_hash = Protocol.ChunkCoords.hash(.{ .x = cx + dx, .z = cz + dz });
                    if (self.sent_chunks.contains(chunk_hash)) continue;

                    const chunk = overworld.getOrCreateChunk(cx + dx, cz + dz) catch continue;

                    var chunk_stream = BinaryStream.init(allocator, null, null);
                    defer chunk_stream.deinit();
                    chunk.serialize(&chunk_stream) catch continue;

                    var pkt_stream = BinaryStream.init(allocator, null, null);
                    defer pkt_stream.deinit();

                    var level_chunk = Protocol.LevelChunkPacket{
                        .x = cx + dx,
                        .z = cz + dz,
                        .dimension = .Overworld,
                        .highestSubChunkCount = 0,
                        .subChunkCount = @intCast(chunk.getSubChunkSendCount()),
                        .cacheEnabled = false,
                        .blobs = &[_]u64{},
                        .data = chunk_stream.getBuffer(),
                    };

                    const serialized = level_chunk.serialize(&pkt_stream) catch continue;
                    packet_batch.append(allocator, allocator.dupe(u8, serialized) catch continue) catch continue;
                    self.sent_chunks.put(chunk_hash, {}) catch {};
                }
            }

            if (packet_batch.items.len >= 8) {
                self.network.sendPackets(self.connection, packet_batch.items) catch {};
                for (packet_batch.items) |pkt| allocator.free(pkt);
                packet_batch.clearRetainingCapacity();
            }
        }

        if (packet_batch.items.len > 0) {
            self.network.sendPackets(self.connection, packet_batch.items) catch {};
        }

        var pub_stream = BinaryStream.init(allocator, null, null);
        defer pub_stream.deinit();

        var update = Protocol.NetworkChunkPublisherUpdatePacket{
            .coordinate = Protocol.BlockPosition{
                .x = @intFromFloat(@floor(self.entity.position.x)),
                .y = @intFromFloat(@floor(self.entity.position.y)),
                .z = @intFromFloat(@floor(self.entity.position.z)),
            },
            .radius = @intCast(self.view_distance * 16),
            .savedChunks = &[_]Protocol.ChunkCoords{},
        };
        const pub_serialized = update.serialize(&pub_stream) catch return;
        self.network.sendPacket(self.connection, pub_serialized) catch {};

        ChunkLoadingTrait.queueChunkStreaming(self) catch {};
    }
};
