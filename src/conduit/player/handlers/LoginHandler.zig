pub fn handle(player: *Player, payload: []const u8) !void {
    const server = player.server;
    const login = LoginPacket.deserialize(CAllocator.get(), payload) catch |err| {
        Logger.ERROR("Failed to deserialize login packet: {any}", .{err});
        return;
    };
    defer {
        CAllocator.get().free(login.identity);
        CAllocator.get().free(login.client);
    }
    _ = server;
    // Decode the full token data once
    const tokens = LoginDecoder.LoginTokens{
        .client = login.client,
        .identity = login.identity,
    };

    var decoded_tokens = LoginDecoder.LoginDecoder.decode(tokens) catch |err| {
        Logger.ERROR("Failed to decode login tokens: {any}", .{err});
        return;
    };
    defer decoded_tokens.deinit(CAllocator.get());

    // Log identity information
    if (decoded_tokens.identity_data) |identity| {
        Logger.DEBUG("Player XUID: {?s}", .{identity.XUID});
        Logger.DEBUG("Player Display Name: {?s}", .{identity.displayName});
        Logger.DEBUG("Player Identity: {?s}", .{identity.identity});
        Logger.DEBUG("Player Title ID: {?s}", .{identity.titleId});
        Logger.DEBUG("Player Sandbox ID: {?s}", .{identity.sandBoxId});
    }

    // Log client information
    if (decoded_tokens.client_data) |client| {
        Logger.DEBUG("Device Model: {?s}", .{client.DeviceModel});
        Logger.DEBUG("Game Version: {?s}", .{client.GameVersion});
        Logger.DEBUG("Device OS: {?d}", .{client.DeviceOS});
        Logger.DEBUG("Language Code: {?s}", .{client.LanguageCode});
        Logger.DEBUG("Platform Online ID: {?s}", .{client.PlatformOnlineId});
    }

    // Log public key if available
    if (decoded_tokens.public_key) |key| {
        Logger.DEBUG("Public Key Length: {d}", .{key.len});
    }

    // Set player info from decoded tokens
    if (decoded_tokens.identity_data) |identity| {
        player.setPlayerInfo(identity.displayName, identity.XUID) catch |err| {
            Logger.ERROR("Failed to set player info: {any}", .{err});
        };
    } else {
        Logger.WARN("No identity data found for player", .{});
    }

    var status = PlayStatus.init(.LoginSuccess);
    const serialized = status.serialize(CAllocator.get());
    defer CAllocator.get().free(serialized);
    player.sendPacket(serialized) catch |err| {
        Logger.ERROR("Failed to send login success packet: {any}", .{err});
    };

    var packs = ResourcePackInfo.init(
        false,
        false,
        false,
        false,
        "00000000-0000-0000-0000-000000000000",
        "1.0.0",
    );
    const serialized_packs = packs.serialize();
    defer CAllocator.get().free(serialized_packs);
    player.sendPacket(serialized_packs) catch |err| {
        Logger.ERROR("Failed to send resource pack info packet: {any}", .{err});
    };
}

const Logger = @import("Logger").Logger;
const CAllocator = @import("CAllocator");

const Player = @import("../Player.zig").Player;
const LoginPacket = @import("../../../protocol/list/Login.zig").Login;

const LoginDecoder = @import("../LoginDecoder.zig");
const PlayStatus = @import("../../../protocol/list/PlayStatus.zig").PlayStatus;
const ResourcePackInfo = @import("../../../protocol/list/ResourcePackInfo.zig").ResourcePackInfo;
