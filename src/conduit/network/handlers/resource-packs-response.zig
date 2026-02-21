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
    Raknet.Logger.INFO("PACKET {any}", .{response});

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
                try player.disconnect();
            }
        },
        .SendPacks => {},

        .Completed => {
            if (network.conduit.getPlayerByConnection(connection)) |player| {
                var str = BinaryStream.init(network.allocator, null, null);
                defer str.deinit();

                const entity_id: i64 = player.runtimeId;
                const runtime_entity_id: u64 = @bitCast(player.runtimeId);

                const properties = Protocol.NBT.Tag{ .Compound = Protocol.NBT.CompoundTag.init(network.allocator, null) };

                const gamerules = [_]Protocol.GameRules.GameRules{
                    Protocol.GameRules.GameRules.init(true, "showcoordinates", .Bool, .{ .Bool = true }),
                };
                const empty_experiments = [_]Protocol.Experiments{};
                const empty_block_definitions = [_]Protocol.NetworkBlockTypeDefinition{};

                var packet = Protocol.StartGamePacket{
                    .entityId = entity_id,
                    .runtimeEntityId = runtime_entity_id,
                    .playerGamemode = .Survival,
                    .playerPosition = Protocol.Vector3f.init(0, 100, 0),
                    .pitch = 0.0,
                    .yaw = 0.0,
                    .seed = 12345678,
                    .biomeType = 0,
                    .biomeName = "plains",
                    .dimension = 0, // Overworld
                    .generator = 1, // Infinite
                    .worldGamemode = .Survival,
                    .hardcore = false,
                    .difficulty = .Normal,
                    .spawnPosition = Protocol.BlockPosition.init(0, 100, 0),
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
                    .permissionLevel = .Member,
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
        },
    }
}
