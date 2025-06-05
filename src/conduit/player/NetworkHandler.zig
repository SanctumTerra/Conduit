const std = @import("std");
const Logger = @import("Logger").Logger;
const Player = @import("Player.zig").Player;
const CAllocator = @import("CAllocator");
const Framer = @import("../../protocol/misc/Framer.zig").Framer;
const BinaryStream = @import("BinaryStream").BinaryStream;
const frameIn = @import("../../raknet/Connection.zig").Connection.frameIn;

const Packets = @import("../../protocol/list/Packets.zig").Packets;
const RequestNetworkSettings = @import("../../protocol/list/login/RequestNetworkSettings.zig").RequestNetworkSettings;
const NetworkSettings = @import("../../protocol/list/login/NetworkSettings.zig").NetworkSettings;
const Login = @import("../../protocol/list/login/Login.zig").Login;
const IdentityData = @import("data/IdentityData.zig").IdentityData;
const PlayStatus = @import("../../protocol/list/login/PlayStatus.zig").PlayStatus;
const ResourcePackInfo = @import("../../protocol/list/login/ResourcePackInfo.zig").ResourcePackInfo;
const ClientCacheStatusPacket = @import("../../protocol/list/login/ClientCacheStatus.zig").ClientCacheStatusPacket;
const ResourcePackResponse = @import("../../protocol/list/login/ResourcePackResponse.zig").ResourcePackResponse;
const ResourcePackStackPacket = @import("../../protocol/list/login/ResourcePackStack.zig").ResourcePackStackPacket;
const StartGamePacket = @import("../../protocol/list/login/StartGame.zig").StartGamePacket;
const Vector3f = @import("../../protocol/misc/Vector3f.zig").Vector3f;
const BlockPosition = @import("../../protocol/misc/BlockPosition.zig").BlockPosition;
const GameRules = @import("../../protocol/list/login/types/GameRules.zig").GameRules;
const Experiments = @import("../../protocol/list/login/types/Experiments.zig").Experiments;
const NetworkBlockTypeDefinition = @import("../../protocol/list/login/StartGame.zig").NetworkBlockTypeDefinition;
const ItemRegistryPacket = @import("../../protocol/list/login/ItemRegistry.zig").ItemRegistryPacket;
const Text = @import("../../protocol/list/player/Text.zig").Text;
const TextType = @import("../../protocol/list/player/Text.zig").TextType;
pub const CompressionMethod = enum(u8) { Zlib = 0, Snappy = 1, NotPresent = 2, None = 0xFF };

pub const NetworkHandler = struct {
    player: *Player,
    allocator: std.mem.Allocator,
    compression: bool,
    compressionThreshold: u16 = 1,

    pub fn init(player: *Player) NetworkHandler {
        return NetworkHandler{
            .player = player,
            .allocator = CAllocator.get(),
            .compression = false,
        };
    }

    /// Already decoded game packets.
    pub fn handlePacket(self: *NetworkHandler, data: []const u8) void {
        const ID = data[0];
        self.player.last_packet = std.time.milliTimestamp();
        switch (ID) {
            Packets.RequestNetworkSettings => self.onRequestNetworkSettings(data),
            Packets.Login => self.onLogin(data),
            Packets.ClientCacheStatus => self.onClientCacheStatus(data),
            Packets.ResourcePackResponse => self.onResourcePackResponse(data),
            Packets.Text => self.onText(data),
            else => {
                Logger.ERROR("Unknown game packet ID: {any}", .{ID});
            },
        }
    }

    pub fn onText(self: *NetworkHandler, data: []const u8) void {
        const packet = Text.deserialize(data);
        Logger.INFO("Text: {s}", .{packet.message});
        if (packet.text_type == TextType.Chat) {
            var text = Text{
                .text_type = TextType.Chat,
                .needs_translation = false,
                .source = self.player.identity_data.displayName orelse "",
                .message = packet.message,
                .parameters = &[_][]const u8{},
                .xuid = self.player.identity_data.xuid orelse "",
                .platform_chat_id = "",
                .filtered = "",
            };
            const serialized = text.serialize();
            self.player.server.broadcastPacket(serialized);
            defer {
                self.allocator.free(serialized);
            }
        }
    }

    pub fn onResourcePackResponse(self: *NetworkHandler, data: []const u8) void {
        const packet = ResourcePackResponse.deserialize(data);
        Logger.INFO("Resource pack response: {}", .{packet.status});
        switch (packet.status) {
            .HaveAllPacks => {
                var resource_pack_stack = ResourcePackStackPacket.init(
                    false,
                    "1.0.0",
                    false,
                    false,
                );
                const serialized = resource_pack_stack.serialize();
                self.player.sendPacket(serialized) catch |err| {
                    Logger.ERROR("Failed to send resource pack stack: {}", .{err});
                };
                defer self.allocator.free(serialized);
            },
            .Completed => {
                var startGamePacket = self.createStartGamePacket();
                defer startGamePacket.deinit();
                const serialized = startGamePacket.serialize();
                Logger.INFO("StartGamePacket", .{});
                self.player.sendPacket(serialized) catch |err| {
                    Logger.ERROR("Failed to send start game packet: {}", .{err});
                };
                defer self.allocator.free(serialized);
                var itemRegistryPacket = ItemRegistryPacket.init();
                const serializedItemRegistryPacket = itemRegistryPacket.serialize();
                self.player.sendPacket(serializedItemRegistryPacket) catch |err| {
                    Logger.ERROR("Failed to send item registry packet: {}", .{err});
                };
                defer self.allocator.free(serializedItemRegistryPacket);
                var playStatus = PlayStatus.init(.PlayerSpawn);
                const serializedPlayStatus = playStatus.serialize();
                self.player.sendPacket(serializedPlayStatus) catch |err| {
                    Logger.ERROR("Failed to send play status: {}", .{err});
                };
                defer self.allocator.free(serializedPlayStatus);
            },
            else => {},
        }
    }

    pub fn onRequestNetworkSettings(self: *NetworkHandler, data: []const u8) void {
        const packet = RequestNetworkSettings.deserialize(data);
        if (packet.protocol != 800) {
            Logger.ERROR("Invalid protocol: {any}", .{packet.protocol});
            return;
        }
        var networkSettings = NetworkSettings.init(
            1,
            @intFromEnum(CompressionMethod.Zlib),
            false,
            1,
            0.0,
        );
        const serialized = networkSettings.serialize();
        self.player.sendPacket(serialized) catch |err| {
            Logger.ERROR("Failed to send network settings: {}", .{err});
        };
        defer self.allocator.free(serialized);
        self.compression = true;
    }

    pub fn onClientCacheStatus(self: *NetworkHandler, data: []const u8) void {
        _ = data;
        var packet = ClientCacheStatusPacket{ .supported = false };
        const serialized = packet.serialize();
        self.player.sendPacket(serialized) catch |err| {
            Logger.ERROR("Failed to send client cache status: {}", .{err});
        };
        defer self.allocator.free(serialized);
    }

    pub fn onLogin(self: *NetworkHandler, data: []const u8) void {
        const packet = Login.deserialize(data);
        self.player.identity_data.parseFromRaw(packet.identity) catch |err| {
            Logger.ERROR("Failed to parse identity data from combined chain: {any}", .{err});
        };

        self.player.client_data.parseFromRaw(packet.client) catch |err| {
            Logger.ERROR("Failed to parse client data: {any}", .{err});
        };

        if (self.player.client_data.ThirdPartyName) |name| {
            Logger.INFO("ThirdPartyName {s}", .{name});
        }
        if (self.player.identity_data.displayName) |name| {
            Logger.INFO("DisplayName {s}", .{name});
        }
        defer {
            self.allocator.free(packet.client);
            self.allocator.free(packet.identity);
        }
        var play_status = PlayStatus.init(.LoginSuccess);
        const serialized = play_status.serialize();
        self.player.sendPacket(serialized) catch |err| {
            Logger.ERROR("Failed to send play status: {}", .{err});
        };
        defer self.allocator.free(serialized);
        var resource_pack_info = ResourcePackInfo.init(
            false,
            false,
            false,
            "00000000-0000-0000-0000-000000000000",
            "1.0.0",
        );
        Logger.INFO("ResourcePacketInfo: {any}", .{resource_pack_info});
        const serialized_resource_pack_info = resource_pack_info.serialize();
        self.player.sendPacket(serialized_resource_pack_info) catch |err| {
            Logger.ERROR("Failed to send resource pack info: {}", .{err});
        };
        defer self.allocator.free(serialized_resource_pack_info);
    }

    /// Decoding Packet && Handling Packet
    pub fn handleGamePacket(self: *NetworkHandler, data: []const u8) void {
        if (data[0] != 0xFE) {
            Logger.WARN("Invalid packet received: {d}", .{data[0]});
            return;
        }
        var decrypted = data[1..];
        const compression = decrypted[0];
        const compressionMethod: CompressionMethod = switch (compression) {
            @intFromEnum(CompressionMethod.None) => .None,
            @intFromEnum(CompressionMethod.Zlib) => .Zlib,
            @intFromEnum(CompressionMethod.Snappy) => .Snappy,
            @intFromEnum(CompressionMethod.NotPresent) => .NotPresent,
            else => .NotPresent,
        };
        if (compressionMethod != .NotPresent) decrypted = decrypted[1..];

        switch (compressionMethod) {
            .Zlib => {
                if (decrypted.len < 1) {
                    Logger.ERROR("Invalid compressed data: empty", .{});
                    return;
                }

                var decompressed_data = std.ArrayList(u8).init(self.allocator);
                defer decompressed_data.deinit();
                var compressed_stream = std.io.fixedBufferStream(decrypted);
                var decompressor = std.compress.flate.decompressor(compressed_stream.reader());

                decompressor.reader().readAllArrayList(&decompressed_data, std.math.maxInt(usize)) catch |err| {
                    Logger.WARN("Raw deflate decompression failed: {any}, trying gzip", .{err});
                    decompressed_data.clearRetainingCapacity();
                    compressed_stream.pos = 0;
                    var gzip_decompressor = std.compress.gzip.decompressor(compressed_stream.reader());

                    gzip_decompressor.reader().readAllArrayList(&decompressed_data, std.math.maxInt(usize)) catch |err2| {
                        Logger.ERROR("Gzip decompression also failed: {any}", .{err2});
                        return;
                    };
                };
                const decompressed = decompressed_data.toOwnedSlice() catch |err| {
                    Logger.ERROR("Failed to get decompressed data: {any}", .{err});
                    return;
                };
                defer self.allocator.free(decompressed);
                const unframed = Framer.unframe(decompressed) catch |err| {
                    Logger.ERROR("Failed to unframe packet: {any} (inflated len: {d})", .{ err, decompressed.len });
                    return;
                };
                defer Framer.freeUnframedData(unframed);

                for (unframed) |frame| {
                    self.handlePacket(frame);
                }
            },
            else => {
                const unframed = Framer.unframe(decrypted) catch |err| {
                    Logger.ERROR("Failed to unframe packet: {any} (inflated len: {d})", .{ err, decrypted.len });
                    return;
                };
                defer Framer.freeUnframedData(unframed);
                for (unframed) |frame| {
                    self.handlePacket(frame);
                }
            },
        }
    }

    pub fn createStartGamePacket(self: *NetworkHandler) StartGamePacket {
        return StartGamePacket{
            .entity_id = 1,
            .runtime_entity_id = 1,
            .player_gamemode = 0, // Creative
            .player_position = Vector3f.init(10, 100, 10),
            .player_pitch = 0,
            .player_yaw = 0,
            .seed = 18446744073709551615,
            .biome_type = 0,
            .biome_name = "",
            .dimension = 0,
            .generator = 1, // Flat
            .world_gamemode = 0, // Survival
            .hardcore = false,
            .difficulty = 2, // Normal
            .spawn_position = BlockPosition{ .x = 0, .y = 100, .z = 0 },
            .achievements_disabled = true,
            .editor_world_type = 0,
            .created_in_editor = false,
            .exported_from_editor = false,
            .day_cycle_stop_time = 83710,
            .edu_offer = 0,
            .edu_features = false,
            .edu_product_uuid = "",
            .rain_level = 0,
            .lightning_level = 0,
            .confirmed_platform_locked_content = false,
            .multiplayer_game = true,
            .broadcast_to_lan = true,
            .xbl_broadcast_mode = 8,
            .platform_broadcast_mode = 8,
            .commands_enabled = true,
            .texture_pack_required = false,
            .gamerules = std.ArrayList(GameRules).init(self.allocator),
            .experiments = std.ArrayList(Experiments).init(self.allocator),
            .experiments_previously_toggled = false,
            .bonus_chest = false,
            .map_enabled = false,
            .permission_level = 2,
            .server_chunk_tick_range = 4,
            .has_locked_behavior_packs = false,
            .has_locked_resource_packs = false,
            .is_from_locked_world = false,
            .use_msa_gamertag_only = false,
            .is_from_world_template = false,
            .is_world_template_option_locked = false,
            .only_spawn_v1_villagers = false,
            .persona_disabled = false,
            .custom_skins_disabled = false,
            .emote_chat_muted = false,
            .game_version = "1.21.80",
            .limited_world_width = 0,
            .limited_world_length = 0,
            .is_new_nether = false,
            .edu_resource_uri_button_name = "",
            .edu_resource_uri_link = "",
            .experimental_gameplay_override = false,
            .chat_restriction_level = 0,
            .disable_player_interactions = false,
            .server_identifier = "",
            .world_identifier = "",
            .scenario_identifier = "",
            .level_id = "",
            .world_name = "Conduit Server",
            .premium_world_template_id = "",
            .is_trial = false,
            .movement_authority = 1,
            .rewind_history_size = 0,
            .server_authoritative_block_breaking = true,
            .current_tick = 0,
            .enchantment_seed = 0,
            .block_network_ids_are_hashes = false,
            .block_palette_checksum = 0,
            .client_side_generation = false,
            .engine = "Conduit",
            .multiplayer_correlation_id = "<raknet>a555-7ece-2f1c-8f69",
            .block_type_definitions = std.ArrayList(NetworkBlockTypeDefinition).init(self.allocator),
            .property_data1 = 0x0a,
            .property_data2 = 0,
            .property_data3 = 0,
            .server_authoritative_inventory = true,
            .server_controlled_sounds = true,
            .world_template_id = "00000000-0000-0000-0000-000000000000",
        };
    }
};
