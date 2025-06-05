const std = @import("std");
const BinaryStream = @import("BinaryStream");
const Vector3f = @import("../../misc/Vector3f.zig").Vector3f;
const BlockPosition = @import("../../misc/BlockPosition.zig").BlockPosition;
const GameRules = @import("./types/GameRules.zig").GameRules;
const Experiments = @import("./types/Experiments.zig").Experiments;
const Packets = @import("../Packets.zig").Packets;
const CAllocator = @import("CAllocator");

pub const NetworkBlockTypeDefinition = struct {
    pub fn write(self: *NetworkBlockTypeDefinition, stream: *BinaryStream.BinaryStream) void {
        _ = self;
        stream.writeVarInt(0, .Big);
    }

    pub fn writeList(definitions: []const NetworkBlockTypeDefinition, stream: *BinaryStream.BinaryStream) void {
        _ = definitions;
        stream.writeVarInt(0, .Big);
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

    // As of 1.21.80 Those are all the fields that are sent in the StartGamePacket.

    pub fn deinit(self: *StartGamePacket) void {
        self.gamerules.deinit();
        self.experiments.deinit();
        self.block_type_definitions.deinit();
    }

    pub fn serialize(self: *StartGamePacket) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.StartGame, .Big);
        stream.writeZigZong(self.entity_id);
        stream.writeVarLong(self.runtime_entity_id, .Big);
        stream.writeZigZag(self.player_gamemode);

        const position_data = self.player_position.serialize();
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
        stream.writeVarInt(self.xbl_broadcast_mode, .Big);
        stream.writeVarInt(self.platform_broadcast_mode, .Big);
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
        stream.writeUUID(self.world_template_id);
        stream.writeBool(self.client_side_generation);
        stream.writeBool(self.block_network_ids_are_hashes);
        stream.writeBool(self.server_controlled_sounds);
        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for StartGamePacket");
    }
};
