pub fn handle(player: *Player, payload: []const u8) !void {
    var packet = try RequestChunkRadius.deserialize(payload);
    defer packet.deinit();
    Logger.DEBUG("Received chunk radius: {}", .{packet.radius});
    var update = ChunkRadiusUpdate.init(packet.radius);
    defer update.deinit();
    const serialized = try update.serialize(CAllocator.get());
    defer CAllocator.get().free(serialized);
    try player.sendPacket(serialized);
}

const RequestChunkRadius = @import("../../../protocol/list/RequestChunkRadius.zig").RequestChunkRadius;
const Player = @import("../Player.zig").Player;
const Logger = @import("Logger").Logger;
const ChunkRadiusUpdate = @import("../../../protocol/list/ChunkRadiusUpdatePacket.zig").ChunkRadiusUpdatePacket;
const CAllocator = @import("CAllocator");
