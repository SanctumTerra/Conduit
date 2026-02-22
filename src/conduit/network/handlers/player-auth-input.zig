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

    const old_pos = player.position;
    const old_rot = player.rotation;
    const old_head_yaw = player.head_yaw;

    player.position = packet.position;
    player.rotation = packet.rotation;
    player.motion = packet.motion;
    player.head_yaw = packet.headYaw;

    var flags: u16 = MoveDeltaFlags.None;
    if (packet.position.x != old_pos.x) flags |= MoveDeltaFlags.HasX;
    if (packet.position.y != old_pos.y) flags |= MoveDeltaFlags.HasY;
    if (packet.position.z != old_pos.z) flags |= MoveDeltaFlags.HasZ;
    if (packet.rotation.x != old_rot.x) flags |= MoveDeltaFlags.HasRotX;
    if (packet.rotation.y != old_rot.y) flags |= MoveDeltaFlags.HasRotY;
    if (packet.headYaw != old_head_yaw) flags |= MoveDeltaFlags.HasRotZ;

    if (flags == MoveDeltaFlags.None) return;

    var move_stream = BinaryStream.init(network.allocator, null, null);
    defer move_stream.deinit();

    const move_packet = Protocol.MoveActorDeltaPacket{
        .runtime_id = @intCast(player.runtimeId),
        .flags = flags,
        .x = packet.position.x,
        .y = packet.position.y,
        .z = packet.position.z,
        .pitch = packet.rotation.x,
        .yaw = packet.rotation.y,
        .head_yaw = packet.headYaw,
    };
    const serialized = try move_packet.serialize(&move_stream);

    var snapshot_buf: [64]?*@import("../../player/player.zig").Player = .{null} ** 64;
    const count = network.conduit.getPlayerSnapshots(&snapshot_buf);
    for (snapshot_buf[0..count]) |maybe_other| {
        const other = maybe_other orelse continue;
        if (other.runtimeId == player.runtimeId) continue;
        if (!other.spawned) continue;
        try network.sendPacket(other.connection, serialized);
    }
}
