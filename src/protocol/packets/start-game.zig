const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NBT = @import("nbt");
const Packet = @import("../root.zig").Packet;
const Gamemode = @import("../enums/gamemode.zig").Gamemode;
const Difficulty = @import("../enums/difficulty.zig").Difficulty;
const PermissionLevel = @import("../enums/permission-level.zig").PermissionLevel;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;
const GameRules = @import("../types/game-rules.zig").GameRules;
const Experiments = @import("../types/experiments.zig").Experiments;
const NetworkBlockTypeDefinition = @import("../types/network-block-type-definition.zig").NetworkBlockTypeDefinition;
const ServerTelemetryData = @import("../types/server-telemetry-data.zig").ServerTelemetryData;
const Uuid = @import("../types/uuid.zig").Uuid;

pub const StartGamePacket = struct {
    entityId: i64,
    runtimeEntityId: u64,
    playerGamemode: Gamemode,
    playerPosition: Vector3f,
    pitch: f32,
    yaw: f32,
    seed: u64,
    biomeType: i16,
    biomeName: []const u8,
    dimension: i32,
    generator: i32,
    worldGamemode: Gamemode,
    hardcore: bool,
    difficulty: Difficulty,
    spawnPosition: BlockPosition,
    achievementsDisabled: bool,
    editorWorldType: i32,
    createdInEditor: bool,
    exportedFromEditor: bool,
    dayCycleStopTime: i32,
    eduOffer: i32,
    eduFeatures: bool,
    eduProductUuid: []const u8,
    rainLevel: f32,
    lightningLevel: f32,
    confirmedPlatformLockedContent: bool,
    multiplayerGame: bool,
    broadcastToLan: bool,
    xblBroadcastMode: u32,
    platformBroadcastMode: u32,
    commandsEnabled: bool,
    texturePacksRequired: bool,
    gamerules: []GameRules,
    experiments: []Experiments,
    experimentsPreviouslyToggled: bool,
    bonusChest: bool,
    mapEnabled: bool,
    permissionLevel: PermissionLevel,
    serverChunkTickRange: i32,
    hasLockedBehaviorPack: bool,
    hasLockedResourcePack: bool,
    isFromLockedWorldTemplate: bool,
    useMsaGamertagsOnly: bool,
    isFromWorldTemplate: bool,
    isWorldTemplateOptionLocked: bool,
    onlySpawnV1Villagers: bool,
    personaDisabled: bool,
    customSkinsDisabled: bool,
    emoteChatMuted: bool,
    gameVersion: []const u8,
    limitedWorldWidth: i32,
    limitedWorldLength: i32,
    isNewNether: bool,
    eduResourceUriButtonName: []const u8,
    eduResourceUriLink: []const u8,
    experimentalGameplayOverride: bool,
    chatRestrictionLevel: u8,
    disablePlayerInteractions: bool,
    levelIdentifier: []const u8,
    levelName: []const u8,
    premiumWorldTemplateId: []const u8,
    isTrial: bool,
    rewindHistorySize: i32,
    serverAuthoritativeBlockBreaking: bool,
    currentTick: u64,
    enchantmentSeed: i32,
    blockTypeDefinitions: []NetworkBlockTypeDefinition,
    multiplayerCorrelationId: []const u8,
    serverAuthoritativeInventory: bool,
    engine: []const u8,
    properties: NBT.Tag,
    blockPaletteChecksum: u64,
    worldTemplateId: []const u8,
    clientSideGeneration: bool,
    blockNetworkIdsAreHashes: bool,
    serverControlledSounds: bool,
    containsServerJoinInfo: bool,
    serverTelemetryData: ServerTelemetryData,

    pub fn serialize(self: *StartGamePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.StartGame);

        try stream.writeZigZong(self.entityId);
        try stream.writeVarLong(self.runtimeEntityId);
        try stream.writeZigZag(@intFromEnum(self.playerGamemode));
        try Vector3f.write(stream, self.playerPosition);
        try stream.writeFloat32(self.pitch, .Little);
        try stream.writeFloat32(self.yaw, .Little);
        try stream.writeInt64(@bitCast(self.seed), .Little);
        try stream.writeInt16(self.biomeType, .Little);
        try stream.writeVarString(self.biomeName);
        try stream.writeZigZag(self.dimension);
        try stream.writeZigZag(self.generator);
        try stream.writeZigZag(@intFromEnum(self.worldGamemode));
        try stream.writeBool(self.hardcore);
        try stream.writeZigZag(@intFromEnum(self.difficulty));
        try BlockPosition.write(stream, self.spawnPosition);
        try stream.writeBool(self.achievementsDisabled);
        try stream.writeZigZag(self.editorWorldType);
        try stream.writeBool(self.createdInEditor);
        try stream.writeBool(self.exportedFromEditor);
        try stream.writeZigZag(self.dayCycleStopTime);
        try stream.writeZigZag(self.eduOffer);
        try stream.writeBool(self.eduFeatures);
        try stream.writeVarString(self.eduProductUuid);
        try stream.writeFloat32(self.rainLevel, .Little);
        try stream.writeFloat32(self.lightningLevel, .Little);
        try stream.writeBool(self.confirmedPlatformLockedContent);
        try stream.writeBool(self.multiplayerGame);
        try stream.writeBool(self.broadcastToLan);
        try stream.writeVarInt(self.xblBroadcastMode);
        try stream.writeVarInt(self.platformBroadcastMode);
        try stream.writeBool(self.commandsEnabled);
        try stream.writeBool(self.texturePacksRequired);
        try GameRules.write(stream, self.gamerules);
        try Experiments.write(stream, self.experiments);
        try stream.writeBool(self.experimentsPreviouslyToggled);
        try stream.writeBool(self.bonusChest);
        try stream.writeBool(self.mapEnabled);
        try stream.writeZigZag(@intFromEnum(self.permissionLevel));
        try stream.writeInt32(self.serverChunkTickRange, .Little);
        try stream.writeBool(self.hasLockedBehaviorPack);
        try stream.writeBool(self.hasLockedResourcePack);
        try stream.writeBool(self.isFromLockedWorldTemplate);
        try stream.writeBool(self.useMsaGamertagsOnly);
        try stream.writeBool(self.isFromWorldTemplate);
        try stream.writeBool(self.isWorldTemplateOptionLocked);
        try stream.writeBool(self.onlySpawnV1Villagers);
        try stream.writeBool(self.personaDisabled);
        try stream.writeBool(self.customSkinsDisabled);
        try stream.writeBool(self.emoteChatMuted);
        try stream.writeVarString(self.gameVersion);
        try stream.writeInt32(self.limitedWorldWidth, .Little);
        try stream.writeInt32(self.limitedWorldLength, .Little);
        try stream.writeBool(self.isNewNether);
        try stream.writeVarString(self.eduResourceUriButtonName);
        try stream.writeVarString(self.eduResourceUriLink);
        try stream.writeBool(self.experimentalGameplayOverride);
        try stream.writeInt8(@bitCast(self.chatRestrictionLevel));
        try stream.writeBool(self.disablePlayerInteractions);
        try stream.writeVarString(self.levelIdentifier);
        try stream.writeVarString(self.levelName);
        try stream.writeVarString(self.premiumWorldTemplateId);
        try stream.writeBool(self.isTrial);
        try stream.writeZigZag(self.rewindHistorySize);
        try stream.writeBool(self.serverAuthoritativeBlockBreaking);
        try stream.writeInt64(@bitCast(self.currentTick), .Little);
        try stream.writeZigZag(self.enchantmentSeed);
        try NetworkBlockTypeDefinition.write(stream, self.blockTypeDefinitions);
        try stream.writeVarString(self.multiplayerCorrelationId);
        try stream.writeBool(self.serverAuthoritativeInventory);
        try stream.writeVarString(self.engine);

        try self.properties.write(stream, .{ .varint = true });

        try stream.writeInt64(@bitCast(self.blockPaletteChecksum), .Little);
        try Uuid.write(stream, self.worldTemplateId);
        try stream.writeBool(self.clientSideGeneration);
        try stream.writeBool(self.blockNetworkIdsAreHashes);
        try stream.writeBool(self.serverControlledSounds);
        try stream.writeBool(self.containsServerJoinInfo);
        try ServerTelemetryData.write(stream, self.serverTelemetryData);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !StartGamePacket {
        _ = try stream.readVarInt();

        const entityId = try stream.readZigZong();
        const runtimeEntityId: u64 = @intCast(try stream.readVarLong());
        const playerGamemode: Gamemode = @enumFromInt(try stream.readZigZag());
        const playerPosition = try Vector3f.read(stream);
        const pitch = try stream.readFloat32(.Little);
        const yaw = try stream.readFloat32(.Little);
        const seed: u64 = @bitCast(try stream.readInt64(.Little));
        const biomeType = try stream.readInt16(.Little);
        const biomeName = try stream.readVarString();
        const dimension = try stream.readZigZag();
        const generator = try stream.readZigZag();
        const worldGamemode: Gamemode = @enumFromInt(try stream.readZigZag());
        const hardcore = try stream.readBool();
        const difficulty: Difficulty = @enumFromInt(try stream.readZigZag());
        const spawnPosition = try BlockPosition.read(stream);
        const achievementsDisabled = try stream.readBool();
        const editorWorldType = try stream.readZigZag();
        const createdInEditor = try stream.readBool();
        const exportedFromEditor = try stream.readBool();
        const dayCycleStopTime = try stream.readZigZag();
        const eduOffer = try stream.readZigZag();
        const eduFeatures = try stream.readBool();
        const eduProductUuid = try stream.readVarString();
        const rainLevel = try stream.readFloat32(.Little);
        const lightningLevel = try stream.readFloat32(.Little);
        const confirmedPlatformLockedContent = try stream.readBool();
        const multiplayerGame = try stream.readBool();
        const broadcastToLan = try stream.readBool();
        const xblBroadcastMode: u32 = @intCast(try stream.readVarInt());
        const platformBroadcastMode: u32 = @intCast(try stream.readVarInt());
        const commandsEnabled = try stream.readBool();
        const texturePacksRequired = try stream.readBool();
        const gamerules = try GameRules.read(stream);
        const experiments = try Experiments.read(stream);
        const experimentsPreviouslyToggled = try stream.readBool();
        const bonusChest = try stream.readBool();
        const mapEnabled = try stream.readBool();
        const permissionLevel: PermissionLevel = @enumFromInt(try stream.readZigZag());
        const serverChunkTickRange = try stream.readInt32(.Little);
        const hasLockedBehaviorPack = try stream.readBool();
        const hasLockedResourcePack = try stream.readBool();
        const isFromLockedWorldTemplate = try stream.readBool();
        const useMsaGamertagsOnly = try stream.readBool();
        const isFromWorldTemplate = try stream.readBool();
        const isWorldTemplateOptionLocked = try stream.readBool();
        const onlySpawnV1Villagers = try stream.readBool();
        const personaDisabled = try stream.readBool();
        const customSkinsDisabled = try stream.readBool();
        const emoteChatMuted = try stream.readBool();
        const gameVersion = try stream.readVarString();
        const limitedWorldWidth = try stream.readInt32(.Little);
        const limitedWorldLength = try stream.readInt32(.Little);
        const isNewNether = try stream.readBool();
        const eduResourceUriButtonName = try stream.readVarString();
        const eduResourceUriLink = try stream.readVarString();
        const experimentalGameplayOverride = try stream.readBool();
        const chatRestrictionLevel: u8 = @bitCast(try stream.readInt8());
        const disablePlayerInteractions = try stream.readBool();
        const levelIdentifier = try stream.readVarString();
        const levelName = try stream.readVarString();
        const premiumWorldTemplateId = try stream.readVarString();
        const isTrial = try stream.readBool();
        const rewindHistorySize = try stream.readZigZag();
        const serverAuthoritativeBlockBreaking = try stream.readBool();
        const currentTick: u64 = @bitCast(try stream.readInt64(.Little));
        const enchantmentSeed = try stream.readZigZag();
        const blockTypeDefinitions = try NetworkBlockTypeDefinition.read(stream);
        const multiplayerCorrelationId = try stream.readVarString();
        const serverAuthoritativeInventory = try stream.readBool();
        const engine = try stream.readVarString();

        const properties = try NBT.Tag.read(stream, stream.allocator, .{ .varint = true });

        const blockPaletteChecksum: u64 = @bitCast(try stream.readInt64(.Little));
        const worldTemplateId = try Uuid.read(stream);
        const clientSideGeneration = try stream.readBool();
        const blockNetworkIdsAreHashes = try stream.readBool();
        const serverControlledSounds = try stream.readBool();
        const containsServerJoinInfo = try stream.readBool();
        const serverTelemetryData = try ServerTelemetryData.read(stream);

        return StartGamePacket{
            .entityId = entityId,
            .runtimeEntityId = runtimeEntityId,
            .playerGamemode = playerGamemode,
            .playerPosition = playerPosition,
            .pitch = pitch,
            .yaw = yaw,
            .seed = seed,
            .biomeType = biomeType,
            .biomeName = biomeName,
            .dimension = dimension,
            .generator = generator,
            .worldGamemode = worldGamemode,
            .hardcore = hardcore,
            .difficulty = difficulty,
            .spawnPosition = spawnPosition,
            .achievementsDisabled = achievementsDisabled,
            .editorWorldType = editorWorldType,
            .createdInEditor = createdInEditor,
            .exportedFromEditor = exportedFromEditor,
            .dayCycleStopTime = dayCycleStopTime,
            .eduOffer = eduOffer,
            .eduFeatures = eduFeatures,
            .eduProductUuid = eduProductUuid,
            .rainLevel = rainLevel,
            .lightningLevel = lightningLevel,
            .confirmedPlatformLockedContent = confirmedPlatformLockedContent,
            .multiplayerGame = multiplayerGame,
            .broadcastToLan = broadcastToLan,
            .xblBroadcastMode = xblBroadcastMode,
            .platformBroadcastMode = platformBroadcastMode,
            .commandsEnabled = commandsEnabled,
            .texturePacksRequired = texturePacksRequired,
            .gamerules = gamerules,
            .experiments = experiments,
            .experimentsPreviouslyToggled = experimentsPreviouslyToggled,
            .bonusChest = bonusChest,
            .mapEnabled = mapEnabled,
            .permissionLevel = permissionLevel,
            .serverChunkTickRange = serverChunkTickRange,
            .hasLockedBehaviorPack = hasLockedBehaviorPack,
            .hasLockedResourcePack = hasLockedResourcePack,
            .isFromLockedWorldTemplate = isFromLockedWorldTemplate,
            .useMsaGamertagsOnly = useMsaGamertagsOnly,
            .isFromWorldTemplate = isFromWorldTemplate,
            .isWorldTemplateOptionLocked = isWorldTemplateOptionLocked,
            .onlySpawnV1Villagers = onlySpawnV1Villagers,
            .personaDisabled = personaDisabled,
            .customSkinsDisabled = customSkinsDisabled,
            .emoteChatMuted = emoteChatMuted,
            .gameVersion = gameVersion,
            .limitedWorldWidth = limitedWorldWidth,
            .limitedWorldLength = limitedWorldLength,
            .isNewNether = isNewNether,
            .eduResourceUriButtonName = eduResourceUriButtonName,
            .eduResourceUriLink = eduResourceUriLink,
            .experimentalGameplayOverride = experimentalGameplayOverride,
            .chatRestrictionLevel = chatRestrictionLevel,
            .disablePlayerInteractions = disablePlayerInteractions,
            .levelIdentifier = levelIdentifier,
            .levelName = levelName,
            .premiumWorldTemplateId = premiumWorldTemplateId,
            .isTrial = isTrial,
            .rewindHistorySize = rewindHistorySize,
            .serverAuthoritativeBlockBreaking = serverAuthoritativeBlockBreaking,
            .currentTick = currentTick,
            .enchantmentSeed = enchantmentSeed,
            .blockTypeDefinitions = blockTypeDefinitions,
            .multiplayerCorrelationId = multiplayerCorrelationId,
            .serverAuthoritativeInventory = serverAuthoritativeInventory,
            .engine = engine,
            .properties = properties,
            .blockPaletteChecksum = blockPaletteChecksum,
            .worldTemplateId = worldTemplateId,
            .clientSideGeneration = clientSideGeneration,
            .blockNetworkIdsAreHashes = blockNetworkIdsAreHashes,
            .serverControlledSounds = serverControlledSounds,
            .containsServerJoinInfo = containsServerJoinInfo,
            .serverTelemetryData = serverTelemetryData,
        };
    }

    pub fn deinit(self: *StartGamePacket, allocator: std.mem.Allocator) void {
        for (self.gamerules) |*rule| {
            rule.deinit(allocator);
        }
        allocator.free(self.gamerules);

        for (self.experiments) |*experiment| {
            experiment.deinit(allocator);
        }
        allocator.free(self.experiments);

        for (self.blockTypeDefinitions) |*definition| {
            definition.deinit(allocator);
        }
        allocator.free(self.blockTypeDefinitions);

        self.properties.deinit(allocator);
        self.serverTelemetryData.deinit(allocator);
    }
};
