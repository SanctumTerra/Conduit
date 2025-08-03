pub fn handle(player: *Player, payload: []const u8) !void {
    const packet = ResourcePackResponse.deserialize(payload) catch |err| {
        Logger.ERROR("Failed to deserialize ResourcePackResponse: {any}", .{err});
        return;
    };

    switch (packet.status) {
        .Completed => {
            Logger.INFO("Resource pack loaded successfully", .{});
            var startGame = StartGamePacket.init(
                player.entityId,
                player.runtimeId,
                0,
                Vector3f.init(0, 0, 0),
                0,
                0,
                0,
                0,
                "",
                0,
                1,
                0,
                false,
                2,
                BlockPosition.init(0, 0, 0),
                false,
                0,
                false,
                false,
                83710,
                0,
                false,
                "",
                0,
                0,
                false, // confirmed_platform_locked_content
                true, // multiplayer_game
                true, // broadcast_to_lan
                8, // xbl_broadcast_mode
                8, // platform_broadcast_mode
                true, // commands_enabled
                false, // texture_pack_required
                false, // experiments_previously_toggled
                false, // bonus_chest
                false, // map_enabled
                2, // permission_level
                4, // server_chunk_tick_range
                false, // has_locked_behavior_packs
                false, // has_locked_resource_packs
                false, // is_from_locked_world
                true, // use_msa_gamertag_only
                false, // is_from_world_template
                false, // is_world_template_option_locked
                false, // only_spawn_v1_villagers
                false, // persona_disabled
                false, // custom_skins_disabled
                false, // emote_chat_muted
                ServerInformation.Version, // game_version
                0, // limited_world_width
                0, // limited_world_length
                true, // is_new_nether
                "", // edu_resource_uri_button_name
                "", // edu_resource_uri_link
                false, // experimental_gameplay_override
                0, // chat_restriction_level
                false, // disable_player_interactions
                "", // server_identifier
                "", // world_identifier
                "", // scenario_identifier
                "", // level_id
                "Conduit Server", // world_name
                "", // premium_world_template_id
                false, // is_trial
                1, // movement_authority
                0, // rewind_history_size
                true, // server_authoritative_block_breaking
                0, // current_tick
                0, // enchantment_seed
                "<raknet>a555-7ece-2f1c-8f69", // multiplayer_correlation_id
                true, // server_authoritative_inventory
                "Conduit", // engine
                0x0a, // property_data1
                0, // property_data2
                0, // property_data3
                0, // block_palette_checksum
                "00000000-0000-0000-0000-000000000000", // world_template_id
                false, // client_side_generation
                false, // block_network_ids_are_hashes
                true, // server_controlled_sounds
                CAllocator.get(),
            );
            defer startGame.deinit();
            const serialized = startGame.serialize() catch |err| {
                Logger.ERROR("Failed to serialize StartGamePacket: {any}", .{err});
                return;
            };
            defer CAllocator.get().free(serialized);
            player.sendPacket(serialized) catch |err| {
                Logger.ERROR("Failed to send StartGamePacket: {any}", .{err});
                return;
            };

            var status = PlayStatus.init(.PlayerSpawn);
            defer status.deinit();
            const serializedStatus = status.serialize(CAllocator.get());
            defer CAllocator.get().free(serializedStatus);
            player.sendPacket(serializedStatus) catch |err| {
                Logger.ERROR("Failed to send PlayStatus: {any}", .{err});
                return;
            };
        },
        .HaveAllPacks => {
            Logger.INFO("Resource pack loaded successfully, but more packs are available", .{});
            var stack = ResourcePackStack.init(
                false,
                ServerInformation.Version,
                false,
                false,
            );
            defer stack.deinit();
            const serialized = stack.serialize() catch |err| {
                Logger.ERROR("Failed to serialize ResourcePackStack: {any}", .{err});
                return;
            };
            defer CAllocator.get().free(serialized);
            player.sendPacket(serialized) catch |err| {
                Logger.ERROR("Failed to send ResourcePackStack: {any}", .{err});
                return;
            };
        },
        else => {},
    }
}

const ResourcePackResponse = @import("../../../protocol/list/ResourcePackResponse.zig").ResourcePackResponse;
const ResourcePackStack = @import("../../../protocol/list/ResourcePackStack.zig").ResourcePackStackPacket;
const StartGamePacket = @import("../../../protocol/list/StartGame.zig").StartGamePacket;
const ServerInformation = @import("../../ServerInformation.zig");
const Player = @import("../Player.zig").Player;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const Vector3f = @import("../../../protocol/types/Vector3f.zig").Vector3f;
const BlockPosition = @import("../../../protocol/types/BlockPosition.zig").BlockPosition;
const PlayStatus = @import("../../../protocol/list/PlayStatus.zig").PlayStatus;
