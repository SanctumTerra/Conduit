pub fn handle(player: *Player, payload: []const u8) !void {
    const server = player.server;
    const packet = RequestNetworkSettings.deserialize(CAllocator.get(), payload);
    Logger.INFO("Session Protocol {d}", .{packet.protocol});

    var settings = NetworkSettings.init(
        server.options.compression_threshold,
        @intFromEnum(server.options.compression_method),
        false,
        0,
        0,
    );
    const serialized = settings.serialize(CAllocator.get()) catch |err| {
        Logger.ERROR("Failed to serialize network settings: {s}", .{@errorName(err)});
        return;
    };

    player.sendPacket(serialized) catch |err| {
        Logger.ERROR("Failed to send network settings: {s}", .{@errorName(err)});
        return;
    };
    defer CAllocator.get().free(serialized);

    player.networkHandler.compression_enabled = true;
    player.networkHandler.compression_method = server.options.compression_method;
    player.networkHandler.compression_threshold = server.options.compression_threshold;
}

const std = @import("std");
const Logger = @import("Logger").Logger;
const Player = @import("../Player.zig").Player;
const CAllocator = @import("CAllocator");
const RequestNetworkSettings = @import("../../../protocol/list/RequestNetworkSettings.zig").RequestNetworkSettings;
const NetworkSettings = @import("../../../protocol/list/NetworkSettings.zig").NetworkSettings;
