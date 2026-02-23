const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;

pub const State = struct {
    current: f32,
    max: f32,
};

fn onAttach(state: *State, entity: *Entity) void {
    entity.attributes.registerWithCurrent(.Health, 0, state.max, state.current, state.max) catch {};
}

fn onDamage(state: *State, entity: *Entity, amount: f32) void {
    state.current -= amount;
    if (state.current < 0) state.current = 0;
    entity.attributes.setCurrent(.Health, state.current);

    const dimension = entity.dimension orelse return;
    const conduit = dimension.world.conduit;

    {
        var stream = BinaryStream.init(conduit.allocator, null, null);
        defer stream.deinit();

        const packet = Protocol.ActorEventPacket{
            .runtimeEntityId = @bitCast(entity.runtime_id),
            .event = .Hurt,
            .data = 0,
        };
        const serialized = packet.serialize(&stream) catch return;

        const snapshots = conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            conduit.network.sendPacket(player.connection, serialized) catch {};
        }
    }

    {
        var attrs = entity.attributes.collectDirty(conduit.allocator) catch return;
        defer attrs.deinit(conduit.allocator);
        if (attrs.items.len == 0) return;

        var stream = BinaryStream.init(conduit.allocator, null, null);
        defer stream.deinit();

        var attr_packet = Protocol.UpdateAttributesPacket{
            .runtime_actor_id = entity.runtime_id,
            .attributes = attrs,
            .tick = 0,
        };
        const serialized = attr_packet.serialize(&stream) catch return;

        const snapshots = conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            conduit.network.sendPacket(player.connection, serialized) catch {};
        }
    }

    if (state.current <= 0) {
        entity.fireEvent(.Death, .{entity});

        var stream = BinaryStream.init(conduit.allocator, null, null);
        defer stream.deinit();

        const death_packet = Protocol.ActorEventPacket{
            .runtimeEntityId = @bitCast(entity.runtime_id),
            .event = .Death,
            .data = 0,
        };
        const serialized = death_packet.serialize(&stream) catch return;

        const snapshots = conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            conduit.network.sendPacket(player.connection, serialized) catch {};
        }

        dimension.removeEntity(entity) catch {};
    }
}

pub const HealthTrait = EntityTrait(State, .{
    .identifier = "health",
    .onAttach = onAttach,
    .onDamage = onDamage,
});
