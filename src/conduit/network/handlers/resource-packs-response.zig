const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

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
                const loaded = player.loadPlayerData();

                const world = network.conduit.getWorld("world");
                const dimension = if (world) |w| w.getDimension("overworld") else null;
                const spawn_pos = if (dimension) |dim| dim.spawn_position else Protocol.BlockPosition.init(0, 100, 0);

                if (!loaded) {
                    player.entity.position = Protocol.Vector3f.init(
                        @floatFromInt(spawn_pos.x),
                        @floatFromInt(spawn_pos.y),
                        @floatFromInt(spawn_pos.z),
                    );
                }

                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    const entity_id: i64 = player.entity.runtime_id;
                    const runtime_entity_id: u64 = @bitCast(player.entity.runtime_id);

                    const properties = Protocol.NBT.Tag{ .Compound = Protocol.NBT.CompoundTag.init(network.allocator, null) };

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
                        .dimension = 0, // Overworld
                        .generator = 1, // Infinite
                        .worldGamemode = .Survival,
                        .hardcore = false,
                        .difficulty = .Normal,
                        .spawnPosition = spawn_pos,
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
                        .levelName = network.conduit.raknet.options.advertisement.level_name,
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
                            network.conduit.raknet.options.advertisement.level_name,
                            player.username,
                        ),
                    };

                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(connection, serialized);
                }

                // AvailableActorIdentifiersPacket
                {
                    const EntityTypeRegistry = @import("../../entity/entity-type-registry.zig");
                    if (EntityTypeRegistry.EntityTypeRegistry.getSerializedPacket()) |serialized| {
                        try network.sendPacket(player.connection, serialized);
                    }
                }

                // ItemRegistryPacket
                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    const ItemPalette = @import("../../items/item-palette.zig");
                    const entries = try ItemPalette.getItemRegistry(network.allocator);
                    defer network.allocator.free(entries);

                    const packet = Protocol.ItemRegistryPacket{ .entries = entries };
                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(player.connection, serialized);
                }

                // CreativeContentPacket
                {
                    if (network.conduit.creative_content) |cc| {
                        try network.sendPacket(player.connection, cc.serialized);
                    }
                }

                // VoxelShapesPacket
                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    const empty_shapes = [_]Protocol.SerializableVoxelShape{};

                    var packet = Protocol.VoxelShapesPacket{
                        .shapes = &empty_shapes,
                        .hashString = "",
                        .registryHandle = 0,
                    };

                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(player.connection, serialized);
                }

                // AvailableCommandsPacket
                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    const serialized = try network.conduit.command_registry.buildAvailableCommandsPacket(&str);
                    try network.sendPacket(player.connection, serialized);
                }

                // SetActorDataPacket
                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    const data = try player.entity.flags.buildDataItems(network.allocator);
                    var packet = Protocol.SetActorDataPacket.init(network.allocator, player.entity.runtime_id, 0, data);
                    defer packet.deinit();

                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(player.connection, serialized);
                }

                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    var attrs = try player.entity.attributes.collectAll(network.allocator);
                    defer attrs.deinit(network.allocator);

                    var packet = Protocol.UpdateAttributesPacket{
                        .runtime_actor_id = player.entity.runtime_id,
                        .attributes = attrs,
                        .tick = 0,
                    };

                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(player.connection, serialized);
                }

                // PlayStatusPacket
                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    const AbilitySet = Protocol.AbilitySet;
                    const abilities = try network.allocator.alloc(AbilitySet, 19);
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

                    const layers = try network.allocator.alloc(Protocol.AbilityLayer, 1);
                    layers[0] = .{
                        .layer_type = @intFromEnum(Protocol.AbilityLayerType.Base),
                        .abilities = abilities,
                        .fly_speed = 0.05,
                        .vertical_fly_speed = 1.0,
                        .walk_speed = 0.1,
                    };

                    var packet = Protocol.UpdateAbilitiesPacket.init(
                        network.allocator,
                        player.entity.runtime_id,
                        @intFromEnum(Protocol.PermissionLevel.Operator),
                        1,
                        layers,
                    );
                    defer packet.deinit();

                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(player.connection, serialized);
                }

                // PlayStatusPacket - PlayerSpawn
                {
                    var str = BinaryStream.init(network.allocator, null, null);
                    defer str.deinit();

                    var packet = Protocol.PlayStatusPacket{
                        .status = .PlayerSpawn,
                    };

                    const serialized = try packet.serialize(&str);
                    try network.sendPacket(player.connection, serialized);
                }
            }
        },
    }
}
