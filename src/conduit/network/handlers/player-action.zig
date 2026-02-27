const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const BlockPermutation = @import("../../world/block/block-permutation.zig").BlockPermutation;
const Events = @import("../../events/types.zig");
const ItemType = @import("../../items/item-type.zig").ItemType;

pub fn handlePlayerAction(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const player = network.conduit.getPlayerByConnection(connection) orelse return;
    const packet = try Protocol.PlayerActionPacket.deserialize(stream);

    switch (packet.action) {
        .Respawn => {},
        .DimensionChangeDone => {},
        .StartItemUseOn => {},
        .StopItemUseOn => {},
        .CreativePlayerDestroyBlock => {
            const world = network.conduit.getWorld("world") orelse return;
            const dimension = world.getDimension("overworld") orelse return;
            const pos = packet.blockPosition;

            const perm = dimension.getPermutation(pos, 0) catch return;
            if (std.mem.eql(u8, perm.identifier, "minecraft:air")) return;

            const default_drop = [_]Events.ItemDrop{.{ .identifier = perm.identifier, .count = 1 }};
            var break_event = Events.BlockBreakEvent{
                .player = player,
                .position = pos,
                .permutation = perm,
                .drops = if (player.gamemode != .Creative) &default_drop else null,
            };
            if (!network.conduit.events.emit(.BlockBreak, &break_event)) return;

            if (dimension.getBlockPtr(pos)) |block| {
                _ = block.fireEvent(.Break, .{ block, player });
                dimension.removeBlock(pos);
            }

            const air = BlockPermutation.resolve(player.entity.allocator, "minecraft:air", null) catch return;
            try dimension.setPermutation(pos, air, 0);

            if (player.gamemode != .Creative) {
                if (break_event.getDrops().len > 0) {
                    const spawn_pos = Protocol.Vector3f.init(
                        @as(f32, @floatFromInt(pos.x)) + 0.5,
                        @as(f32, @floatFromInt(pos.y)) + 0.5,
                        @as(f32, @floatFromInt(pos.z)) + 0.5,
                    );
                    var spawned = std.ArrayList(*@import("../../entity/entity.zig").Entity){ .items = &.{}, .capacity = 0 };
                    defer spawned.deinit(network.allocator);
                    for (break_event.getDrops()) |drop| {
                        const drop_item_type = ItemType.get(drop.identifier) orelse continue;
                        const entity = dimension.spawnItemEntity(drop_item_type, drop.count, spawn_pos) catch continue;
                        spawned.append(network.allocator, entity) catch {};
                    }
                    break_event.entities = spawned.items;
                }
            }

            const perm_id: u32 = @bitCast(perm.network_id);
            var ev_stream = BinaryStream.init(network.allocator, null, null);
            defer ev_stream.deinit();
            const ev_pkt = Protocol.LevelEventPacket{
                .event = .ParticlesDestroyBlock,
                .position = pos.toVector3f(),
                .data = @bitCast(perm_id),
            };
            const ev_serialized = ev_pkt.serialize(&ev_stream) catch return;

            const air_id: u32 = @bitCast(air.network_id);
            const snapshots = network.conduit.getPlayerSnapshots();
            for (snapshots) |p| {
                if (!p.spawned) continue;
                network.sendPacket(p.connection, ev_serialized) catch {};
                var s = BinaryStream.init(network.allocator, null, null);
                defer s.deinit();
                const update = Protocol.UpdateBlockPacket{
                    .position = pos,
                    .networkBlockId = air_id,
                };
                const serialized = try update.serialize(&s);
                try network.sendPacket(p.connection, serialized);
            }
        },
        else => {
            Raknet.Logger.DEBUG("Unhandled PlayerAction: {any}", .{packet.action});
        },
    }
}
