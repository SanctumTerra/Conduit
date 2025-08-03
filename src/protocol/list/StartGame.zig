const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Vector3f = @import("../types/Vector3f.zig").Vector3f;
const BlockPosition = @import("../types/BlockPosition.zig").BlockPosition;
const GameRules = @import("../types/GameRules.zig").GameRules;
const Experiments = @import("../types/Experiments.zig").Experiments;
const Packets = @import("../enums/Packets.zig").Packets;

pub const NetworkBlockTypeDefinition = struct {
    pub fn write(self: *NetworkBlockTypeDefinition, stream: *BinaryStream) void {
        _ = self;
        stream.writeVarInt(0);
    }

    pub fn writeList(definitions: []const NetworkBlockTypeDefinition, stream: *BinaryStream) void {
        _ = definitions;
        stream.writeVarInt(0);
    }
};

pub const StartGamePacket = struct {
    entity_id: i64, // ZigZong
    runtime_entity_id: u64, // VarLong
    player_gamemode: i32, // ZigZag
    player_position: Vector3f, // Vector3f
    player_pitch: f32, // Float32 Endianess Little.
    player_yaw: f32, // Float32 Endianess Little.
    seed: u64, // Uint64 Endianess Little.
    biome_type: i16, // Int16 Endianess Little
    biome_name: []const u8, // VarString
    dimension: i32, // ZigZag
    generator: i32, // ZigZag
    world_gamemode: i32, // ZigZag
    hardcore: bool, // Bool
    difficulty: i32, // ZigZag
    spawn_position: BlockPosition, // BlockPosition
    achievements_disabled: bool, // Bool
    editor_world_type: i32, // ZigZag
    created_in_editor: bool, // Bool
    exported_from_editor: bool, // Bool
    day_cycle_stop_time: i32, // ZigZag
    edu_offer: i32, // ZigZag
    edu_features: bool, // Bool
    edu_product_uuid: []const u8, // VarString
    rain_level: f32, // Float32 Endianess Little.
    lightning_level: f32, // Float32 Endianess Little.
    confirmed_platform_locked_content: bool, // Bool
    multiplayer_game: bool, // Bool
    broadcast_to_lan: bool, // Bool
    xbl_broadcast_mode: u32, // VarInt
    platform_broadcast_mode: u32, // VarInt
    commands_enabled: bool, // Bool
    texture_pack_required: bool, // Bool
    gamerules: std.ArrayList(GameRules), // Array of GameRules
    experiments: std.ArrayList(Experiments), // Array of Experiments
    experiments_previously_toggled: bool, // Bool
    bonus_chest: bool, // Bool
    map_enabled: bool, // Bool
    permission_level: u8, // Uint8
    server_chunk_tick_range: i32, // Int32 Endianess Little
    has_locked_behavior_packs: bool, // Bool
    has_locked_resource_packs: bool, // Bool
    is_from_locked_world: bool, // Bool
    use_msa_gamertag_only: bool, // Bool
    is_from_world_template: bool, // Bool
    is_world_template_option_locked: bool, // Bool
    only_spawn_v1_villagers: bool, // Bool
    persona_disabled: bool, // Bool
    custom_skins_disabled: bool, // Bool
    emote_chat_muted: bool, // Bool
    game_version: []const u8, // VarString
    limited_world_width: i32, // Int32 Endianess Little
    limited_world_length: i32, // Int32 Endianess Little
    is_new_nether: bool, // Bool
    edu_resource_uri_button_name: []const u8, // VarString
    edu_resource_uri_link: []const u8, // VarString - Changed from edu_resource_uri_button_url
    experimental_gameplay_override: bool, // Bool
    chat_restriction_level: u8, // Uint8
    disable_player_interactions: bool, // Bool - Changed from disable_player_interaction
    server_identifier: []const u8, // VarString - Changed from server_identfier
    world_identifier: []const u8, // VarString
    scenario_identifier: []const u8, // VarString
    level_id: []const u8, // VarString - Changed from level_identifier
    world_name: []const u8, // VarString
    premium_world_template_id: []const u8, // VarString
    is_trial: bool, // Bool
    movement_authority: i64, // ZigZag
    rewind_history_size: i64, // ZigZag
    server_authoritative_block_breaking: bool, // Bool - Changed from server_authorative_block_breaking
    current_tick: i64, // Int64 Endianess Little - Changed from currentTick
    enchantment_seed: i64, // ZigZag
    block_type_definitions: std.ArrayList(NetworkBlockTypeDefinition), // Array - Changed from network_block_type_definitions
    multiplayer_correlation_id: []const u8, // VarString
    server_authoritative_inventory: bool, // Bool
    engine: []const u8, // VarString
    property_data1: u8, // Uint8
    property_data2: u8, // Uint8
    property_data3: u8, // Uint8
    block_palette_checksum: u64, // Uint64 Endianess Little.
    world_template_id: []const u8, // UUID.
    client_side_generation: bool, // Bool
    block_network_ids_are_hashes: bool, // Bool - Changed from block_netword_ids_are_hashes
    server_controlled_sounds: bool, // Bool - Changed from server_controlled_sound
    allocator: std.mem.Allocator,
    // As of 1.21.80 Those are all the fields that are sent in the StartGamePacket.

    pub fn init(
        entity_id: i64,
        runtime_entity_id: u64,
        player_gamemode: i32,
        player_position: Vector3f,
        player_pitch: f32,
        player_yaw: f32,
        seed: u64,
        biome_type: i16,
        biome_name: []const u8,
        dimension: i32,
        generator: i32,
        world_gamemode: i32,
        hardcore: bool,
        difficulty: i32,
        spawn_position: BlockPosition,
        achievements_disabled: bool,
        editor_world_type: i32,
        created_in_editor: bool,
        exported_from_editor: bool,
        day_cycle_stop_time: i32,
        edu_offer: i32,
        edu_features: bool,
        edu_product_uuid: []const u8,
        rain_level: f32,
        lightning_level: f32,
        confirmed_platform_locked_content: bool,
        multiplayer_game: bool,
        broadcast_to_lan: bool,
        xbl_broadcast_mode: u32,
        platform_broadcast_mode: u32,
        commands_enabled: bool,
        texture_pack_required: bool,
        experiments_previously_toggled: bool,
        bonus_chest: bool,
        map_enabled: bool,
        permission_level: u8,
        server_chunk_tick_range: i32,
        has_locked_behavior_packs: bool,
        has_locked_resource_packs: bool,
        is_from_locked_world: bool,
        use_msa_gamertag_only: bool,
        is_from_world_template: bool,
        is_world_template_option_locked: bool,
        only_spawn_v1_villagers: bool,
        persona_disabled: bool,
        custom_skins_disabled: bool,
        emote_chat_muted: bool,
        game_version: []const u8,
        limited_world_width: i32,
        limited_world_length: i32,
        is_new_nether: bool,
        edu_resource_uri_button_name: []const u8,
        edu_resource_uri_link: []const u8,
        experimental_gameplay_override: bool,
        chat_restriction_level: u8,
        disable_player_interactions: bool,
        server_identifier: []const u8,
        world_identifier: []const u8,
        scenario_identifier: []const u8,
        level_id: []const u8,
        world_name: []const u8,
        premium_world_template_id: []const u8,
        is_trial: bool,
        movement_authority: i64,
        rewind_history_size: i64,
        server_authoritative_block_breaking: bool,
        current_tick: i64,
        enchantment_seed: i64,
        multiplayer_correlation_id: []const u8,
        server_authoritative_inventory: bool,
        engine: []const u8,
        property_data1: u8,
        property_data2: u8,
        property_data3: u8,
        block_palette_checksum: u64,
        world_template_id: []const u8,
        client_side_generation: bool,
        block_network_ids_are_hashes: bool,
        server_controlled_sounds: bool,
        allocator: std.mem.Allocator,
    ) StartGamePacket {
        return StartGamePacket{
            .entity_id = entity_id,
            .runtime_entity_id = runtime_entity_id,
            .player_gamemode = player_gamemode,
            .player_position = player_position,
            .player_pitch = player_pitch,
            .player_yaw = player_yaw,
            .seed = seed,
            .biome_type = biome_type,
            .biome_name = biome_name,
            .dimension = dimension,
            .generator = generator,
            .world_gamemode = world_gamemode,
            .hardcore = hardcore,
            .difficulty = difficulty,
            .spawn_position = spawn_position,
            .achievements_disabled = achievements_disabled,
            .editor_world_type = editor_world_type,
            .created_in_editor = created_in_editor,
            .exported_from_editor = exported_from_editor,
            .day_cycle_stop_time = day_cycle_stop_time,
            .edu_offer = edu_offer,
            .edu_features = edu_features,
            .edu_product_uuid = edu_product_uuid,
            .rain_level = rain_level,
            .lightning_level = lightning_level,
            .confirmed_platform_locked_content = confirmed_platform_locked_content,
            .multiplayer_game = multiplayer_game,
            .broadcast_to_lan = broadcast_to_lan,
            .xbl_broadcast_mode = xbl_broadcast_mode,
            .platform_broadcast_mode = platform_broadcast_mode,
            .commands_enabled = commands_enabled,
            .texture_pack_required = texture_pack_required,
            .gamerules = std.ArrayList(GameRules).init(allocator),
            .experiments = std.ArrayList(Experiments).init(allocator),
            .experiments_previously_toggled = experiments_previously_toggled,
            .bonus_chest = bonus_chest,
            .map_enabled = map_enabled,
            .permission_level = permission_level,
            .server_chunk_tick_range = server_chunk_tick_range,
            .has_locked_behavior_packs = has_locked_behavior_packs,
            .has_locked_resource_packs = has_locked_resource_packs,
            .is_from_locked_world = is_from_locked_world,
            .use_msa_gamertag_only = use_msa_gamertag_only,
            .is_from_world_template = is_from_world_template,
            .is_world_template_option_locked = is_world_template_option_locked,
            .only_spawn_v1_villagers = only_spawn_v1_villagers,
            .persona_disabled = persona_disabled,
            .custom_skins_disabled = custom_skins_disabled,
            .emote_chat_muted = emote_chat_muted,
            .game_version = game_version,
            .limited_world_width = limited_world_width,
            .limited_world_length = limited_world_length,
            .is_new_nether = is_new_nether,
            .edu_resource_uri_button_name = edu_resource_uri_button_name,
            .edu_resource_uri_link = edu_resource_uri_link,
            .experimental_gameplay_override = experimental_gameplay_override,
            .chat_restriction_level = chat_restriction_level,
            .disable_player_interactions = disable_player_interactions,
            .server_identifier = server_identifier,
            .world_identifier = world_identifier,
            .scenario_identifier = scenario_identifier,
            .level_id = level_id,
            .world_name = world_name,
            .premium_world_template_id = premium_world_template_id,
            .is_trial = is_trial,
            .movement_authority = movement_authority,
            .rewind_history_size = rewind_history_size,
            .server_authoritative_block_breaking = server_authoritative_block_breaking,
            .current_tick = current_tick,
            .enchantment_seed = enchantment_seed,
            .block_type_definitions = std.ArrayList(NetworkBlockTypeDefinition).init(allocator),
            .multiplayer_correlation_id = multiplayer_correlation_id,
            .server_authoritative_inventory = server_authoritative_inventory,
            .engine = engine,
            .property_data1 = property_data1,
            .property_data2 = property_data2,
            .property_data3 = property_data3,
            .block_palette_checksum = block_palette_checksum,
            .world_template_id = world_template_id,
            .client_side_generation = client_side_generation,
            .block_network_ids_are_hashes = block_network_ids_are_hashes,
            .server_controlled_sounds = server_controlled_sounds,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StartGamePacket) void {
        self.gamerules.deinit();
        self.experiments.deinit();
        self.block_type_definitions.deinit();
    }

    pub fn serialize(self: *StartGamePacket) ![]const u8 {
        var stream = BinaryStream.init(self.allocator, &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.StartGame);
        stream.writeZigZong(self.entity_id);
        stream.writeVarLong(self.runtime_entity_id);
        stream.writeZigZag(self.player_gamemode);

        const position_data = self.player_position.serialize();
        defer CAllocator.get().free(position_data);
        stream.write(position_data);
        stream.writeFloat32(self.player_pitch, .Little);
        stream.writeFloat32(self.player_yaw, .Little);
        stream.writeUint64(self.seed, .Little);

        stream.writeInt16(self.biome_type, .Little);
        stream.writeVarString(self.biome_name);

        stream.writeZigZag(self.dimension);
        stream.writeZigZag(self.generator);
        stream.writeZigZag(self.world_gamemode);
        stream.writeBool(self.hardcore);
        stream.writeZigZag(self.difficulty);
        const spawn_position_data = BlockPosition.serialize(&self.spawn_position);
        defer CAllocator.get().free(spawn_position_data);
        stream.write(spawn_position_data);
        stream.writeBool(self.achievements_disabled);
        stream.writeZigZag(self.editor_world_type);
        stream.writeBool(self.created_in_editor);
        stream.writeBool(self.exported_from_editor);
        stream.writeZigZag(self.day_cycle_stop_time);
        stream.writeZigZag(self.edu_offer);
        stream.writeBool(self.edu_features);
        stream.writeVarString(self.edu_product_uuid);
        stream.writeFloat32(self.rain_level, .Little);
        stream.writeFloat32(self.lightning_level, .Little);
        stream.writeBool(self.confirmed_platform_locked_content);
        stream.writeBool(self.multiplayer_game);
        stream.writeBool(self.broadcast_to_lan);
        stream.writeVarInt(self.xbl_broadcast_mode);
        stream.writeVarInt(self.platform_broadcast_mode);
        stream.writeBool(self.commands_enabled);
        stream.writeBool(self.texture_pack_required);
        GameRules.writeList(self.gamerules.items, &stream);
        Experiments.writeList(self.experiments.items, &stream);
        stream.writeBool(self.experiments_previously_toggled);
        stream.writeBool(self.bonus_chest);
        stream.writeBool(self.map_enabled);
        stream.writeUint8(self.permission_level);
        stream.writeInt32(self.server_chunk_tick_range, .Little);
        stream.writeBool(self.has_locked_behavior_packs);
        stream.writeBool(self.has_locked_resource_packs);
        stream.writeBool(self.is_from_locked_world);
        stream.writeBool(self.use_msa_gamertag_only);
        stream.writeBool(self.is_from_world_template);
        stream.writeBool(self.is_world_template_option_locked);
        stream.writeBool(self.only_spawn_v1_villagers);
        stream.writeBool(self.persona_disabled);
        stream.writeBool(self.custom_skins_disabled);
        stream.writeBool(self.emote_chat_muted);
        stream.writeVarString(self.game_version);
        stream.writeInt32(self.limited_world_width, .Little);
        stream.writeInt32(self.limited_world_length, .Little);
        stream.writeBool(self.is_new_nether);
        stream.writeVarString(self.edu_resource_uri_button_name);
        stream.writeVarString(self.edu_resource_uri_link);
        stream.writeBool(self.experimental_gameplay_override);
        stream.writeUint8(self.chat_restriction_level);
        stream.writeBool(self.disable_player_interactions);
        stream.writeVarString(self.server_identifier);
        stream.writeVarString(self.world_identifier);
        stream.writeVarString(self.scenario_identifier);
        stream.writeVarString(self.level_id);
        stream.writeVarString(self.world_name);
        stream.writeVarString(self.premium_world_template_id);
        stream.writeBool(self.is_trial);
        stream.writeZigZag(@as(i32, @intCast(self.movement_authority)));
        stream.writeZigZag(@as(i32, @intCast(self.rewind_history_size)));
        stream.writeBool(self.server_authoritative_block_breaking);
        stream.writeInt64(self.current_tick, .Little);
        stream.writeZigZag(@as(i32, @intCast(self.enchantment_seed)));
        NetworkBlockTypeDefinition.writeList(self.block_type_definitions.items, &stream);
        stream.writeVarString(self.multiplayer_correlation_id);
        stream.writeBool(self.server_authoritative_inventory);
        stream.writeVarString(self.engine);
        stream.writeUint8(self.property_data1);
        stream.writeUint8(self.property_data2);
        stream.writeUint8(self.property_data3);
        stream.writeUint64(self.block_palette_checksum, .Little);
        try stream.writeUuid(self.world_template_id);
        stream.writeBool(self.client_side_generation);
        stream.writeBool(self.block_network_ids_are_hashes);
        stream.writeBool(self.server_controlled_sounds);
        return stream.getBufferOwned(CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize StartGamePacket {any}", .{err});
            return "";
        };
    }
};

const Logger = @import("Logger").Logger;
const CAllocator = @import("CAllocator");
