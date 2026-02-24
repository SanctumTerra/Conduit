const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const BlockContainer = @import("../../container/block-container.zig").BlockContainer;
const ChestTrait = @import("../../world/block/traits/chest.zig").ChestTrait;

pub fn handleContainerClose(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.ContainerClosePacket.deserialize(stream);

    if (player.opened_container) |container| {
        if (container.occupants.get(player)) |_| {
            container.close(player, false);

            if (container.occupants.count() == 0) {
                trySendBlockClose(network, container);
            }
        } else {
            player.opened_container = null;
            var str = BinaryStream.init(network.allocator, null, null);
            defer str.deinit();

            const response = Protocol.ContainerClosePacket{
                .identifier = packet.identifier,
                .container_type = packet.container_type,
                .server_initiated = false,
            };
            const serialized = try response.serialize(&str);
            try network.sendPacket(connection, serialized);
        }
    } else {
        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        const response = Protocol.ContainerClosePacket{
            .identifier = packet.identifier,
            .container_type = packet.container_type,
            .server_initiated = true,
        };
        const serialized = try response.serialize(&str);
        try network.sendPacket(connection, serialized);
    }
}

fn trySendBlockClose(network: *NetworkHandler, container: *@import("../../container/container.zig").Container) void {
    const block_container: *BlockContainer = @fieldParentPtr("base", container);
    const position = block_container.position orelse return;

    const world = network.conduit.getWorld("world") orelse return;
    const dimension = world.getDimension("overworld") orelse return;
    const block = dimension.getBlockPtr(position) orelse return;

    if (!block.hasTrait(ChestTrait.identifier)) return;

    const state = block.getTraitState(ChestTrait) orelse return;

    sendCloseAt(network, block, position);
    if (state.pair_position) |pair_pos| {
        sendCloseAt(network, block, pair_pos);
    }
}

fn sendCloseAt(network: *NetworkHandler, block: *@import("../../world/block/block.zig").Block, position: Protocol.BlockPosition) void {
    const perm = block.getPermutation(0) catch return;
    const snapshots = network.conduit.getPlayerSnapshots();

    for (snapshots) |p| {
        if (!p.spawned) continue;
        {
            var s = BinaryStream.init(network.allocator, null, null);
            defer s.deinit();
            const event_packet = Protocol.BlockEventPacket{
                .position = position,
                .event_type = .ChangeState,
                .data = 0,
            };
            const serialized = event_packet.serialize(&s) catch continue;
            network.sendPacket(p.connection, serialized) catch {};
        }
        {
            var s = BinaryStream.init(network.allocator, null, null);
            defer s.deinit();
            const sound_packet = Protocol.LevelSoundEventPacket{
                .event = .ChestClosed,
                .position = .{
                    .x = @floatFromInt(position.x),
                    .y = @floatFromInt(position.y),
                    .z = @floatFromInt(position.z),
                },
                .data = perm.network_id,
                .actorIdentifier = "",
                .isBabyMob = false,
                .isGlobal = false,
            };
            const serialized = sound_packet.serialize(&s) catch continue;
            network.sendPacket(p.connection, serialized) catch {};
        }
    }
}
