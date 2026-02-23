const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleInventoryTransaction(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.InventoryTransactionPacket.deserialize(stream);

    switch (packet.transactionType) {
        .UseItemOnEntity => {
            const data = packet.transactionData.useItemOnEntity;
            if (data.actionType == 1) {
                const target = network.conduit.getEntityByRuntimeId(@bitCast(data.targetEntityRuntimeId)) orelse return;

                const dx = target.position.x - player.entity.position.x;
                const dz = target.position.z - player.entity.position.z;
                const dist = @sqrt(dx * dx + dz * dz);
                if (dist > 0.001) {
                    const kb_strength: f32 = 0.3;
                    target.motion.x = (dx / dist) * kb_strength;
                    target.motion.y = 0.3;
                    target.motion.z = (dz / dist) * kb_strength;

                    broadcastMotion(network, target);
                }

                target.fireEvent(.Damage, .{ target, @as(f32, 1.0) });
            }
        },
        else => {},
    }
}

fn broadcastMotion(network: *NetworkHandler, entity: *const @import("../../entity/entity.zig").Entity) void {
    const allocator = network.conduit.allocator;
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    const motion_packet = Protocol.SetActorMotionPacket{
        .runtimeEntityId = @bitCast(entity.runtime_id),
        .motion = entity.motion,
    };
    const serialized = motion_packet.serialize(&stream) catch return;

    const snapshots = network.conduit.getPlayerSnapshots();
    for (snapshots) |p| {
        if (!p.spawned) continue;
        network.sendPacket(p.connection, serialized) catch {};
    }
}
