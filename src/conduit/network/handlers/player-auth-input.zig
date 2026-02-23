const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const MoveDeltaFlags = Protocol.MoveDeltaFlags;

pub fn handlePlayerAuthInput(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.PlayerAuthInputPacket.deserialize(stream);

    player.entity.position = packet.position;
    player.entity.rotation = packet.rotation;
    player.entity.motion = .{ .x = packet.motion.x, .y = 0, .z = packet.motion.y };
    player.entity.head_yaw = packet.headYaw;

    {
        var flags_changed = false;
        if (packet.inputData.hasFlag(.StartSneaking)) {
            player.entity.flags.setFlag(.Sneaking, true);
            flags_changed = true;
        }
        if (packet.inputData.hasFlag(.StopSneaking)) {
            player.entity.flags.setFlag(.Sneaking, false);
            flags_changed = true;
        }
        if (flags_changed) try player.broadcastActorFlags();
    }

    var move_stream = BinaryStream.init(network.allocator, null, null);
    defer move_stream.deinit();

    const move_packet = Protocol.MoveActorDeltaPacket{
        .runtime_id = @intCast(player.entity.runtime_id),
        .flags = MoveDeltaFlags.All,
        .x = packet.position.x,
        .y = packet.position.y,
        .z = packet.position.z,
        .pitch = packet.rotation.x,
        .yaw = packet.rotation.y,
        .head_yaw = packet.headYaw,
    };
    const serialized = try move_packet.serialize(&move_stream);

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |other| {
        if (other.entity.runtime_id == player.entity.runtime_id) continue;
        if (!other.spawned) continue;
        try network.sendPacket(other.connection, serialized);
    }
}
