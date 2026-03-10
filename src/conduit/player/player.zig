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

pub const PLAYER_EYE_HEIGHT: f32 = 1.62;
pub const DROP_HEIGHT_ABOVE_FEET: f32 = 1.3;
pub const DROP_FORWARD_SPEED: f32 = 0.4;

pub fn internalToWorldFeetPosition(pos: Protocol.Vector3f) Protocol.Vector3f {
    return Protocol.Vector3f.init(pos.x, pos.y - PLAYER_EYE_HEIGHT, pos.z);
}

pub fn worldFeetToInternalPosition(pos: Protocol.Vector3f) Protocol.Vector3f {
    return Protocol.Vector3f.init(pos.x, pos.y + PLAYER_EYE_HEIGHT, pos.z);
}

pub fn playerDropSpawnPosition(pos: Protocol.Vector3f) Protocol.Vector3f {
    const feet = internalToWorldFeetPosition(pos);
    return Protocol.Vector3f.init(feet.x, feet.y + DROP_HEIGHT_ABOVE_FEET, feet.z);
}

pub fn playerDropVelocity(rotation: Protocol.Vector2f) Protocol.Vector3f {
    const yaw = rotation.y * std.math.pi / 180.0;
    const pitch = rotation.x * std.math.pi / 180.0;
    return Protocol.Vector3f.init(
        -@sin(yaw) * @cos(pitch) * DROP_FORWARD_SPEED,
        -@sin(pitch) * DROP_FORWARD_SPEED,
        @cos(yaw) * @cos(pitch) * DROP_FORWARD_SPEED,
    );
}

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
    visible_players: std.AutoHashMap(i64, void),
    spawned: bool = false,
    join_startup_started: bool = false,
    pending_dimension: ?*Dimension = null,
    opened_container: ?*Container = null,
    block_target: ?Protocol.BlockPosition = null,
    gamemode: Protocol.GameMode = .Creative,

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
            .visible_players = std.AutoHashMap(i64, void).init(allocator),
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
            .visibility_tick = ChunkLoadingTrait.VISIBILITY_UPDATE_INTERVAL - 1,
        });
        try self.entity.addTrait(chunk_loading);

        const cursor_trait = try CursorTrait.create(allocator, .{
            .container = undefined,
        });
        try self.entity.addTrait(cursor_trait);
    }

    pub fn deinit(self: *Player) void {
        self.sent_chunks.deinit();
        self.visible_players.deinit();
        self.loginData.deinit();
        self.entity.deinit();
    }

    pub fn getCommandPermission(_: *Player) void {}

    pub fn disconnect(self: *Player, reason: ?[]const u8) !void {
        if (reason) |msg| {
            var stream = BinaryStream.init(self.entity.allocator, null, null);
            defer stream.deinit();
            var dp = Protocol.DisconnectPacket{
                .hideScreen = false,
                .reason = .Kicked,
                .message = msg,
                .filtered = msg,
            };
            if (dp.serialize(&stream)) |data| {
                self.network.sendImmediate(self.connection, data) catch {};
            } else |_| {}
        }

        self.savePlayerData();
        self.network.conduit.tasks.cancelByOwner("chunk_streaming", self.entity.runtime_id, ChunkLoadingTrait.destroyStreamState);
        self.network.conduit.tasks.cancelByOwner("join_startup", self.entity.runtime_id, null);
        self.network.conduit.tasks.cancelByOwner("player_init", self.entity.runtime_id, null);
        self.releaseChunks();

        const allocator = self.entity.allocator;
        const snapshots = self.network.conduit.getPlayerSnapshots();

        {
            var stream = BinaryStream.init(allocator, null, null);
            defer stream.deinit();
            const remove = Protocol.RemoveEntityPacket{ .uniqueEntityId = self.entity.unique_id };
            const serialized = remove.serialize(&stream) catch null;
            if (serialized) |data| {
                for (snapshots) |other| {
                    if (other.entity.runtime_id == self.entity.runtime_id) continue;
                    if (!other.spawned) continue;
                    _ = other.visible_players.remove(self.entity.runtime_id);
                    self.network.sendPacket(other.connection, data) catch {};
                }
            }
        }

        {
            var stream = BinaryStream.init(allocator, null, null);
            defer stream.deinit();
            const entry = [_]Protocol.PlayerListEntry{.{
                .uuid = self.uuid,
                .entityUniqueId = self.entity.runtime_id,
                .username = self.username,
                .xuid = self.xuid,
                .skin = null,
                .buildPlatform = 0,
            }};
            var packet = Protocol.PlayerListPacket{
                .action = .Remove,
                .entries = &entry,
            };
            const serialized = packet.serialize(&stream, allocator) catch null;
            if (serialized) |data| {
                for (snapshots) |other| {
                    if (other.entity.runtime_id == self.entity.runtime_id) continue;
                    if (!other.spawned) continue;
                    self.network.sendPacket(other.connection, data) catch {};
                }
            }
        }

        self.network.conduit.removePlayer(self);
        self.deinit();
        self.entity.allocator.destroy(self);
    }

    pub fn savePlayerData(self: *Player) void {
        const dimension = self.entity.dimension orelse return;
        dimension.world.provider.writePlayer(self.uuid, self) catch |err| {
            Raknet.Logger.ERROR("Failed to save player {s}: {any}", .{ self.username, err });
        };
    }

    pub fn loadPlayerData(self: *Player) bool {
        const dimension = self.entity.dimension orelse return false;
        return dimension.world.provider.readPlayer(self.uuid, self) catch false;
    }

    pub fn transferToDimension(self: *Player, dimension: *Dimension) void {
        self.savePlayerData();
        self.network.conduit.tasks.cancelByOwner("chunk_streaming", self.entity.runtime_id, ChunkLoadingTrait.destroyStreamState);
        self.network.conduit.tasks.cancelByOwner("join_startup", self.entity.runtime_id, null);
        self.network.conduit.tasks.cancelByOwner("player_init", self.entity.runtime_id, null);
        self.releaseChunks();
        if (self.entity.getTraitState(ChunkLoadingTrait.ChunkLoadingTrait)) |state| {
            const s: *ChunkLoadingTrait.State = @ptrCast(@alignCast(state));
            s.initialized = false;
        }

        const spawn = dimension.spawn_position;
        const pos = Protocol.Vector3f.init(
            @as(f32, @floatFromInt(spawn.x)) + 0.5,
            @as(f32, @floatFromInt(spawn.y)),
            @as(f32, @floatFromInt(spawn.z)) + 0.5,
        );

        const current_type = if (self.entity.dimension) |d| d.dimension_type else null;
        if (current_type != null and current_type.? == dimension.dimension_type) {
            self.entity.dimension = dimension;
            self.entity.position = pos;

            var stream = BinaryStream.init(self.entity.allocator, null, null);
            defer stream.deinit();
            const move = Protocol.MovePlayerPacket{
                .runtime_id = @bitCast(self.entity.runtime_id),
                .position = pos,
                .pitch = 0,
                .yaw = 0,
                .head_yaw = 0,
                .mode = .Teleport,
                .on_ground = false,
            };
            const serialized = move.serialize(&stream) catch return;
            self.network.sendPacket(self.connection, serialized) catch {};
        } else {
            self.spawned = false;
            self.pending_dimension = dimension;

            var stream = BinaryStream.init(self.entity.allocator, null, null);
            defer stream.deinit();
            var pkt = Protocol.ChangeDimensionPacket{
                .dimension = dimension.dimension_type,
                .position = pos,
                .respawn = false,
            };
            const serialized = pkt.serialize(&stream) catch return;
            self.network.sendPacket(self.connection, serialized) catch {};
        }
    }

    fn releaseChunks(self: *Player) void {
        const dimension = self.entity.dimension orelse return;
        const allocator = self.entity.allocator;

        var hashes = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
        var it = self.sent_chunks.keyIterator();
        while (it.next()) |key| {
            hashes.append(allocator, key.*) catch {};
        }
        self.sent_chunks.clearAndFree();
        dimension.releaseUnrenderedChunks(hashes.items);
        hashes.deinit(allocator);
    }

    pub fn onSpawn(self: *Player) !void {
        Raknet.Logger.DEBUG("Player {s} has spawned.", .{self.username});

        if (self.entity.getTraitState(InventoryTrait)) |state| {
            var s: *InventoryTrait.TraitState = state;
            s.container.update();
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
            if (other.entity.runtime_id != self.entity.runtime_id and !other.visible_players.contains(self.entity.runtime_id)) continue;
            try self.network.sendPacket(other.connection, serialized);
        }
    }

    fn sendSpawnChunks(self: *Player) !void {
        const allocator = self.entity.allocator;

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

test "player drop velocity matches pocketmine direction toss" {
    const vel = playerDropVelocity(Protocol.Vector2f.init(0, 0));

    try std.testing.expectApproxEqAbs(@as(f32, 0), vel.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vel.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), vel.z, 0.0001);
}
