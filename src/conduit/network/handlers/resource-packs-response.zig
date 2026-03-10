const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Player = @import("../../player/player.zig").Player;
const EntityTypeRegistry = @import("../../entity/entity-type-registry.zig");

const JoinStartupStage = enum(u8) {
    prepare_player,
    send_start_game,
    send_registry_batch,
    send_commands,
    send_entity_batch,
    send_abilities_spawn,
};

const JoinStartupTask = struct {
    network: *NetworkHandler,
    player: *Player,
    stage: JoinStartupStage = .prepare_player,
    spawn_pos: Protocol.BlockPosition = Protocol.BlockPosition.init(0, 100, 0),
};

pub fn handleResourcePack(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const response = try Protocol.ResourcePackResponsePacket.deserialize(stream);

    switch (response.response) {
        .HaveAllPacks => {
            var str = BinaryStream.init(network.allocator, null, null);
            defer str.deinit();

            const empty_packs = [_]Protocol.ResourceIdVersions{};
            const empty_experiments = [_]Protocol.Experiments{};

            var stack = Protocol.ResourcePackStackPacket{
                .mustAccept = false,
                .texturePacks = &empty_packs,
                .gameVersion = "26.0",
                .experiments = &empty_experiments,
                .experimentsPreviouslyToggled = false,
                .hasEditorPacks = false,
            };

            const serialized = try stack.serialize(&str);
            try network.sendPacket(connection, serialized);
        },
        .None => {
            Raknet.Logger.DEBUG("Unhandled ResourcePackClientResponse: None", .{});
        },
        .Refused => {
            if (network.conduit.getPlayerByConnection(connection)) |player| {
                try player.disconnect(null);
            }
        },
        .SendPacks => {},
        .Completed => {
            if (network.conduit.getPlayerByConnection(connection)) |player| {
                try queueJoinStartup(network, player);
            }
        },
    }
}

fn queueJoinStartup(network: *NetworkHandler, player: *Player) !void {
    if (player.join_startup_started) return;
    player.join_startup_started = true;

    const state = try network.allocator.create(JoinStartupTask);
    errdefer network.allocator.destroy(state);
    state.* = .{
        .network = network,
        .player = player,
    };

    try network.conduit.tasks.enqueue(.{
        .func = runJoinStartupTask,
        .ctx = @ptrCast(state),
        .name = "join_startup",
        .owner_id = player.entity.runtime_id,
        .cleanup = destroyJoinStartupTask,
    });
}

fn runJoinStartupTask(ctx: *anyopaque) bool {
    const state: *JoinStartupTask = @ptrCast(@alignCast(ctx));
    return runJoinStartupTaskImpl(state) catch |err| {
        Raknet.Logger.ERROR("Join startup failed for {s}: {any}", .{ state.player.username, err });
        state.player.join_startup_started = false;
        return true;
    };
}

fn runJoinStartupTaskImpl(state: *JoinStartupTask) !bool {
    const player = state.player;
    if (!player.connection.active or state.network.conduit.getPlayerByConnection(player.connection) == null) {
        player.join_startup_started = false;
        return true;
    }

    switch (state.stage) {
        .prepare_player => {
            const world = state.network.conduit.getWorld("world");
            const dimension = if (world) |w| w.getDimension("overworld") else null;
            player.entity.dimension = dimension;

            const loaded = player.loadPlayerData();
            state.spawn_pos = if (dimension) |dim| dim.spawn_position else Protocol.BlockPosition.init(0, 100, 0);

            if (!loaded) {
                player.entity.position = Protocol.Vector3f.init(
                    @floatFromInt(state.spawn_pos.x),
                    @floatFromInt(state.spawn_pos.y),
                    @floatFromInt(state.spawn_pos.z),
                );
            }

            state.stage = .send_start_game;
            return false;
        },
        .send_start_game => {
            try sendStartGameBatch(state);
            state.stage = .send_registry_batch;
            return false;
        },
        .send_registry_batch => {
            try sendRegistryBatch(state);
            state.stage = .send_commands;
            return false;
        },
        .send_commands => {
            try sendCommandsPacket(state);
            state.stage = .send_entity_batch;
            return false;
        },
        .send_entity_batch => {
            try sendEntityDataBatch(state);
            state.stage = .send_abilities_spawn;
            return false;
        },
        .send_abilities_spawn => {
            try sendAbilitiesAndSpawnBatch(state);
            return true;
        },
    }
}

fn destroyJoinStartupTask(ctx: *anyopaque) void {
    const state: *JoinStartupTask = @ptrCast(@alignCast(ctx));
    state.network.allocator.destroy(state);
}

fn sendStartGameBatch(state: *JoinStartupTask) !void {
    var batched_packets = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer batched_packets.deinit(state.network.allocator);
    var owned_packets = std.ArrayList([]u8){ .items = &.{}, .capacity = 0 };
    defer freeOwnedPackets(state.network.allocator, &owned_packets);

    var str = BinaryStream.init(state.network.allocator, null, null);
    defer str.deinit();

    const player = state.player;
    const entity_id: i64 = player.entity.runtime_id;
    const runtime_entity_id: u64 = @bitCast(player.entity.runtime_id);
    const properties = Protocol.NBT.Tag{ .Compound = Protocol.NBT.CompoundTag.init(state.network.allocator, null) };
    const gamerules = [_]Protocol.GameRules.GameRules{
        Protocol.GameRules.GameRules.init(true, "showcoordinates", .Bool, .{ .Bool = true }),
    };
    const empty_experiments = [_]Protocol.Experiments{};
    const empty_block_definitions = [_]Protocol.NetworkBlockTypeDefinition{};

    var packet = Protocol.StartGamePacket{
        .entityId = entity_id,
        .runtimeEntityId = runtime_entity_id,
        .playerGamemode = .Creative,
        .playerPosition = player.entity.position,
        .pitch = player.entity.rotation.y,
        .yaw = player.entity.rotation.x,
        .seed = 12345678,
        .biomeType = 0,
        .biomeName = "plains",
        .dimension = 0,
        .generator = 1,
        .worldGamemode = .Survival,
        .hardcore = false,
        .difficulty = .Normal,
        .spawnPosition = state.spawn_pos,
        .achievementsDisabled = true,
        .editorWorldType = 0,
        .createdInEditor = false,
        .exportedFromEditor = false,
        .dayCycleStopTime = -1,
        .eduOffer = 0,
        .eduFeatures = false,
        .eduProductUuid = "",
        .rainLevel = 0.0,
        .lightningLevel = 0.0,
        .confirmedPlatformLockedContent = false,
        .multiplayerGame = true,
        .broadcastToLan = true,
        .xblBroadcastMode = 6,
        .platformBroadcastMode = 6,
        .commandsEnabled = true,
        .texturePacksRequired = false,
        .gamerules = @constCast(&gamerules),
        .experiments = &empty_experiments,
        .experimentsPreviouslyToggled = false,
        .bonusChest = false,
        .mapEnabled = false,
        .permissionLevel = .Operator,
        .serverChunkTickRange = 4,
        .hasLockedBehaviorPack = false,
        .hasLockedResourcePack = false,
        .isFromLockedWorldTemplate = false,
        .useMsaGamertagsOnly = false,
        .isFromWorldTemplate = false,
        .isWorldTemplateOptionLocked = false,
        .onlySpawnV1Villagers = false,
        .personaDisabled = false,
        .customSkinsDisabled = false,
        .emoteChatMuted = false,
        .gameVersion = "1.21.50",
        .limitedWorldWidth = 0,
        .limitedWorldLength = 0,
        .isNewNether = true,
        .eduResourceUriButtonName = "",
        .eduResourceUriLink = "",
        .experimentalGameplayOverride = false,
        .chatRestrictionLevel = 0,
        .disablePlayerInteractions = false,
        .levelIdentifier = "Conduit",
        .levelName = state.network.conduit.raknet.options.advertisement.level_name,
        .premiumWorldTemplateId = "00000000-0000-0000-0000-000000000000",
        .isTrial = false,
        .rewindHistorySize = 0,
        .serverAuthoritativeBlockBreaking = true,
        .currentTick = 0,
        .enchantmentSeed = 0,
        .blockTypeDefinitions = &empty_block_definitions,
        .multiplayerCorrelationId = "<raknet>",
        .serverAuthoritativeInventory = true,
        .engine = "Conduit",
        .properties = properties,
        .blockPaletteChecksum = 0,
        .worldTemplateId = "00000000-0000-0000-0000-000000000000",
        .clientSideGeneration = false,
        .blockNetworkIdsAreHashes = true,
        .serverControlledSounds = true,
        .containsServerJoinInfo = false,
        .serverTelemetryData = Protocol.ServerTelemetryData.init(
            "Conduit",
            "conduit.default",
            state.network.conduit.raknet.options.advertisement.level_name,
            player.username,
        ),
    };

    try appendOwnedPacket(state.network, &batched_packets, &owned_packets, try packet.serialize(&str));
    try state.network.sendPackets(player.connection, batched_packets.items);
}

fn sendRegistryBatch(state: *JoinStartupTask) !void {
    var batched_packets = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer batched_packets.deinit(state.network.allocator);
    var owned_packets = std.ArrayList([]u8){ .items = &.{}, .capacity = 0 };
    defer freeOwnedPackets(state.network.allocator, &owned_packets);

    if (EntityTypeRegistry.EntityTypeRegistry.getSerializedPacket()) |serialized| {
        try batched_packets.append(state.network.allocator, serialized);
    }
    if (state.network.conduit.serialized_item_registry) |serialized| {
        try batched_packets.append(state.network.allocator, serialized);
    }
    if (state.network.conduit.creative_content) |cc| {
        try batched_packets.append(state.network.allocator, cc.serialized);
    }

    var str = BinaryStream.init(state.network.allocator, null, null);
    defer str.deinit();
    const empty_shapes = [_]Protocol.SerializableVoxelShape{};
    var packet = Protocol.VoxelShapesPacket{
        .shapes = &empty_shapes,
        .hashString = "",
        .registryHandle = 0,
    };
    try appendOwnedPacket(state.network, &batched_packets, &owned_packets, try packet.serialize(&str));

    if (batched_packets.items.len > 0) {
        try state.network.sendPackets(state.player.connection, batched_packets.items);
    }
}

fn sendCommandsPacket(state: *JoinStartupTask) !void {
    var str = BinaryStream.init(state.network.allocator, null, null);
    defer str.deinit();
    const serialized = try state.network.conduit.command_registry.buildAvailableCommandsPacket(&str);
    try state.network.sendPacket(state.player.connection, serialized);
}

fn sendEntityDataBatch(state: *JoinStartupTask) !void {
    var batched_packets = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer batched_packets.deinit(state.network.allocator);
    var owned_packets = std.ArrayList([]u8){ .items = &.{}, .capacity = 0 };
    defer freeOwnedPackets(state.network.allocator, &owned_packets);

    {
        var str = BinaryStream.init(state.network.allocator, null, null);
        defer str.deinit();

        const data = try state.player.entity.flags.buildDataItems(state.network.allocator);
        var packet = Protocol.SetActorDataPacket.init(state.network.allocator, state.player.entity.runtime_id, 0, data);
        defer packet.deinit();
        try appendOwnedPacket(state.network, &batched_packets, &owned_packets, try packet.serialize(&str));
    }

    {
        var str = BinaryStream.init(state.network.allocator, null, null);
        defer str.deinit();

        var attrs = try state.player.entity.attributes.collectAll(state.network.allocator);
        defer attrs.deinit(state.network.allocator);

        var packet = Protocol.UpdateAttributesPacket{
            .runtime_actor_id = state.player.entity.runtime_id,
            .attributes = attrs,
            .tick = 0,
        };
        try appendOwnedPacket(state.network, &batched_packets, &owned_packets, try packet.serialize(&str));
    }

    if (batched_packets.items.len > 0) {
        try state.network.sendPackets(state.player.connection, batched_packets.items);
    }
}

fn sendAbilitiesAndSpawnBatch(state: *JoinStartupTask) !void {
    var batched_packets = std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
    defer batched_packets.deinit(state.network.allocator);
    var owned_packets = std.ArrayList([]u8){ .items = &.{}, .capacity = 0 };
    defer freeOwnedPackets(state.network.allocator, &owned_packets);

    {
        var str = BinaryStream.init(state.network.allocator, null, null);
        defer str.deinit();

        const AbilitySet = Protocol.AbilitySet;
        const abilities = try state.network.allocator.alloc(AbilitySet, 19);
        abilities[0] = .{ .ability = .Build, .value = true };
        abilities[1] = .{ .ability = .Mine, .value = true };
        abilities[2] = .{ .ability = .DoorsAndSwitches, .value = true };
        abilities[3] = .{ .ability = .OpenContainers, .value = true };
        abilities[4] = .{ .ability = .AttackPlayers, .value = true };
        abilities[5] = .{ .ability = .AttackMobs, .value = true };
        abilities[6] = .{ .ability = .OperatorCommands, .value = true };
        abilities[7] = .{ .ability = .Teleport, .value = true };
        abilities[8] = .{ .ability = .Invulnerable, .value = true };
        abilities[9] = .{ .ability = .Flying, .value = false };
        abilities[10] = .{ .ability = .MayFly, .value = true };
        abilities[11] = .{ .ability = .InstantBuild, .value = true };
        abilities[12] = .{ .ability = .Lightning, .value = false };
        abilities[13] = .{ .ability = .FlySpeed, .value = true };
        abilities[14] = .{ .ability = .WalkSpeed, .value = true };
        abilities[15] = .{ .ability = .Muted, .value = false };
        abilities[16] = .{ .ability = .WorldBuilder, .value = false };
        abilities[17] = .{ .ability = .NoClip, .value = false };
        abilities[18] = .{ .ability = .PrivilegedBuilder, .value = false };

        const layers = try state.network.allocator.alloc(Protocol.AbilityLayer, 1);
        layers[0] = .{
            .layer_type = @intFromEnum(Protocol.AbilityLayerType.Base),
            .abilities = abilities,
            .fly_speed = 0.05,
            .vertical_fly_speed = 1.0,
            .walk_speed = 0.1,
        };

        var packet = Protocol.UpdateAbilitiesPacket.init(
            state.network.allocator,
            state.player.entity.runtime_id,
            @intFromEnum(Protocol.PermissionLevel.Operator),
            1,
            layers,
        );
        defer packet.deinit();
        try appendOwnedPacket(state.network, &batched_packets, &owned_packets, try packet.serialize(&str));
    }

    {
        var str = BinaryStream.init(state.network.allocator, null, null);
        defer str.deinit();

        var packet = Protocol.PlayStatusPacket{
            .status = .PlayerSpawn,
        };
        try appendOwnedPacket(state.network, &batched_packets, &owned_packets, try packet.serialize(&str));
    }

    if (batched_packets.items.len > 0) {
        try state.network.sendPackets(state.player.connection, batched_packets.items);
    }
}

fn appendOwnedPacket(
    network: *NetworkHandler,
    packets: *std.ArrayList([]const u8),
    owned_packets: *std.ArrayList([]u8),
    serialized: []const u8,
) !void {
    const owned = try network.allocator.dupe(u8, serialized);
    errdefer network.allocator.free(owned);
    try owned_packets.append(network.allocator, owned);
    try packets.append(network.allocator, owned);
}

fn freeOwnedPackets(allocator: std.mem.Allocator, owned_packets: *std.ArrayList([]u8)) void {
    for (owned_packets.items) |packet| allocator.free(packet);
    owned_packets.deinit(allocator);
}
