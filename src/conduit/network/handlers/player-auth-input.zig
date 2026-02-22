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

    player.position = packet.position;
    player.rotation = packet.rotation;
    player.motion = packet.motion;
    player.head_yaw = packet.headYaw;

    // Flags
    {
        var flags_changed = false;
        if (packet.inputData.hasFlag(.StartSneaking)) {
            player.flags.setFlag(.Sneaking, true);
            flags_changed = true;
        }
        if (packet.inputData.hasFlag(.StopSneaking)) {
            player.flags.setFlag(.Sneaking, false);
            flags_changed = true;
        }
        if (flags_changed) try player.broadcastActorFlags();
    }

    var move_stream = BinaryStream.init(network.allocator, null, null);
    defer move_stream.deinit();

    const move_packet = Protocol.MoveActorDeltaPacket{
        .runtime_id = @intCast(player.runtimeId),
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
        if (other.runtimeId == player.runtimeId) continue;
        if (!other.spawned) continue;
        try network.sendPacket(other.connection, serialized);
    }
}
