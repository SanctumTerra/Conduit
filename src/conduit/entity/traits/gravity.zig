const std = @import("std");
const Protocol = @import("protocol");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const MoveDeltaFlags = Protocol.MoveDeltaFlags;

pub const State = struct {
    force: f32,
    falling_distance: f32,
    falling_ticks: u32,
    on_ground: bool,
};

fn isAirAt(dimension: *Dimension, x: i32, y: i32, z: i32) bool {
    const pos = Protocol.BlockPosition{ .x = x, .y = y, .z = z };
    const perm = dimension.getPermutation(pos, 0) catch return true;
    return std.mem.eql(u8, perm.identifier, "minecraft:air");
}

fn hasMotion(entity: *Entity) bool {
    return @abs(entity.motion.x) > 0.001 or @abs(entity.motion.y) > 0.001 or @abs(entity.motion.z) > 0.001;
}

fn onTick(state: *State, entity: *Entity) void {
    const dimension = entity.dimension orelse return;

    entity.motion.y += state.force;

    const new_pos = entity.position.add(entity.motion);
    entity.position = Protocol.Vector3f.init(new_pos.x, new_pos.y, new_pos.z);

    const bx = @as(i32, @intFromFloat(@floor(entity.position.x)));
    const by = @as(i32, @intFromFloat(@floor(entity.position.y - 0.01)));
    const bz = @as(i32, @intFromFloat(@floor(entity.position.z)));

    const ground = !isAirAt(dimension, bx, by, bz);

    if (ground) {
        const land_y: f32 = @floatFromInt(by + 1);
        if (entity.position.y < land_y) {
            entity.position.y = land_y;
        }

        if (entity.motion.y < 0) {
            entity.motion.y = 0;
        }

        entity.motion.x *= 0.6;
        entity.motion.z *= 0.6;
        if (@abs(entity.motion.x) < 0.001) entity.motion.x = 0;
        if (@abs(entity.motion.z) < 0.001) entity.motion.z = 0;

        if (!state.on_ground and state.falling_distance > 0) {
            broadcastMove(entity, dimension, true);
            state.falling_distance = 0;
            state.falling_ticks = 0;
        }
        state.on_ground = true;
    } else {
        state.on_ground = false;
        if (entity.motion.y < 0) {
            state.falling_distance += @abs(entity.motion.y);
            state.falling_ticks += 1;
        }
        broadcastMove(entity, dimension, false);
    }
}

fn broadcastMove(entity: *Entity, dimension: *Dimension, on_ground: bool) void {
    const conduit = dimension.world.conduit;
    const allocator = conduit.allocator;

    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    var packet = Protocol.MoveActorDeltaPacket.init(@bitCast(entity.runtime_id));
    packet.flags = MoveDeltaFlags.HasX | MoveDeltaFlags.HasY | MoveDeltaFlags.HasZ;
    if (on_ground) packet.flags |= MoveDeltaFlags.OnGround;
    packet.x = entity.position.x;
    packet.y = entity.position.y;
    packet.z = entity.position.z;

    const serialized = packet.serialize(&stream) catch return;

    const snapshots = conduit.getPlayerSnapshots();
    for (snapshots) |player| {
        if (!player.spawned) continue;
        conduit.network.sendPacket(player.connection, serialized) catch {};
    }
}

pub const GravityTrait = EntityTrait(State, .{
    .identifier = "gravity",
    .entities = &.{
        "minecraft:zombie",
        "minecraft:skeleton",
        "minecraft:creeper",
        "minecraft:spider",
        "minecraft:cow",
        "minecraft:pig",
        "minecraft:sheep",
        "minecraft:chicken",
        "minecraft:wolf",
        "minecraft:villager",
        "minecraft:enderman",
        "minecraft:slime",
        "minecraft:silverfish",
        "minecraft:blaze",
        "minecraft:witch",
        "minecraft:bat",
        "minecraft:iron_golem",
        "minecraft:snow_golem",
        "minecraft:ocelot",
        "minecraft:horse",
        "minecraft:rabbit",
        "minecraft:polar_bear",
        "minecraft:llama",
        "minecraft:parrot",
        "minecraft:dolphin",
        "minecraft:drowned",
        "minecraft:phantom",
        "minecraft:cat",
        "minecraft:panda",
        "minecraft:fox",
        "minecraft:bee",
        "minecraft:hoglin",
        "minecraft:piglin",
        "minecraft:strider",
        "minecraft:zoglin",
        "minecraft:goat",
        "minecraft:axolotl",
        "minecraft:glow_squid",
        "minecraft:warden",
        "minecraft:allay",
        "minecraft:frog",
        "minecraft:camel",
        "minecraft:sniffer",
        "minecraft:armadillo",
        "minecraft:bogged",
        "minecraft:breeze",
        "minecraft:item",
    },
    .default_state = .{
        .force = -0.08,
        .falling_distance = 0,
        .falling_ticks = 0,
        .on_ground = false,
    },
    .onTick = onTick,
});
