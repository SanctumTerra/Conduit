const std = @import("std");
const Protocol = @import("protocol");

const World = @import("../world.zig").World;
const Chunk = @import("../chunk/chunk.zig").Chunk;
const BlockPermutation = @import("../block/block-permutation.zig").BlockPermutation;
const Block = @import("../block/block.zig").Block;
const TerrainGenerator = @import("../generator/terrain-generator.zig").TerrainGenerator;
const ThreadedGenerator = @import("../generator/threaded-generator.zig").ThreadedGenerator;
const Entity = @import("../../entity/entity.zig").Entity;
const EntityType = @import("../../entity/entity-type.zig").EntityType;

pub const ChunkHash = i64;

pub fn chunkHash(x: i32, z: i32) ChunkHash {
    return (@as(i64, x) << 32) | @as(i64, @as(u32, @bitCast(z)));
}

pub const Dimension = struct {
    world: *World,
    allocator: std.mem.Allocator,
    identifier: []const u8,
    dimension_type: Protocol.DimensionType,
    chunks: std.AutoHashMap(ChunkHash, *Chunk),
    entities: std.AutoHashMap(i64, *Entity),
    spawn_position: Protocol.BlockPosition,
    simulation_distance: i32,
    generator: ?*ThreadedGenerator,

    pub fn init(
        world: *World,
        allocator: std.mem.Allocator,
        identifier: []const u8,
        dimension_type: Protocol.DimensionType,
        generator: ?*ThreadedGenerator,
    ) Dimension {
        return Dimension{
            .world = world,
            .allocator = allocator,
            .identifier = identifier,
            .dimension_type = dimension_type,
            .chunks = std.AutoHashMap(ChunkHash, *Chunk).init(allocator),
            .entities = std.AutoHashMap(i64, *Entity).init(allocator),
            .spawn_position = Protocol.BlockPosition{
                .x = 0,
                .y = 32767,
                .z = 0,
            },
            .simulation_distance = 4,
            .generator = generator,
        };
    }

    pub fn deinit(self: *Dimension) void {
        var entity_iter = self.entities.valueIterator();
        while (entity_iter.next()) |entity| {
            entity.*.deinit();
            self.allocator.destroy(entity.*);
        }
        self.entities.deinit();

        var iter = self.chunks.valueIterator();
        while (iter.next()) |chunk| {
            chunk.*.deinit();
            self.allocator.destroy(chunk.*);
        }
        self.chunks.deinit();
        if (self.generator) |gen| gen.deinit();
    }

    pub fn getChunk(self: *Dimension, x: i32, z: i32) ?*Chunk {
        return self.chunks.get(chunkHash(x, z));
    }

    pub fn getOrCreateChunk(self: *Dimension, x: i32, z: i32) !*Chunk {
        const hash = chunkHash(x, z);
        if (self.chunks.get(hash)) |chunk| return chunk;

        const chunk = if (self.generator) |gen|
            try gen.generate(x, z)
        else blk: {
            const c = try self.allocator.create(Chunk);
            c.* = Chunk.init(self.allocator, x, z, self.dimension_type);
            break :blk c;
        };

        try self.chunks.put(hash, chunk);
        return chunk;
    }

    pub fn removeChunk(self: *Dimension, x: i32, z: i32) void {
        const hash = chunkHash(x, z);
        if (self.chunks.fetchRemove(hash)) |entry| {
            var chunk = entry.value;
            chunk.deinit();
            self.allocator.destroy(chunk);
        }
    }

    pub fn releaseUnrenderedChunks(self: *Dimension, hashes: []const i64) void {
        const conduit = self.world.conduit;
        const snapshots = conduit.getPlayerSnapshots();
        const spawn_cx = self.spawn_position.x >> 4;
        const spawn_cz = self.spawn_position.z >> 4;
        const sim = self.simulation_distance;
        for (hashes) |h| {
            const coords = Protocol.ChunkCoords.unhash(h);
            const dx = coords.x - spawn_cx;
            const dz = coords.z - spawn_cz;
            if (dx * dx + dz * dz <= sim * sim) continue;

            var still_needed = false;
            for (snapshots) |player| {
                if (player.sent_chunks.contains(h)) {
                    still_needed = true;
                    break;
                }
            }
            if (!still_needed) {
                if (self.chunks.fetchRemove(h)) |entry| {
                    var chunk = entry.value;
                    chunk.deinit();
                    self.allocator.destroy(chunk);
                }
            }
        }
    }

    pub fn getPermutation(self: *Dimension, pos: Protocol.BlockPosition, layer: usize) !*BlockPermutation {
        const cx = pos.x >> 4;
        const cz = pos.z >> 4;
        const chunk = try self.getOrCreateChunk(cx, cz);
        return chunk.getPermutation(pos.x, pos.y, pos.z, layer);
    }

    pub fn setPermutation(self: *Dimension, pos: Protocol.BlockPosition, permutation: *BlockPermutation, layer: usize) !void {
        const cx = pos.x >> 4;
        const cz = pos.z >> 4;
        const chunk = try self.getOrCreateChunk(cx, cz);
        try chunk.setPermutation(pos.x, pos.y, pos.z, permutation, layer);
    }

    pub fn getBlock(self: *Dimension, pos: Protocol.BlockPosition) Block {
        return Block.init(self.allocator, self, pos);
    }

    pub fn loadSpawnChunks(self: *Dimension) !void {
        const spawn_cx = self.spawn_position.x >> 4;
        const spawn_cz = self.spawn_position.z >> 4;
        const sim = self.simulation_distance;
        var cx: i32 = spawn_cx - sim;
        while (cx <= spawn_cx + sim) : (cx += 1) {
            var cz: i32 = spawn_cz - sim;
            while (cz <= spawn_cz + sim) : (cz += 1) {
                if ((cx - spawn_cx) * (cx - spawn_cx) + (cz - spawn_cz) * (cz - spawn_cz) > sim * sim) continue;
                _ = try self.getOrCreateChunk(cx, cz);
            }
        }
    }

    pub fn getEntity(self: *Dimension, runtime_id: i64) ?*Entity {
        return self.entities.get(runtime_id);
    }

    pub fn spawnEntity(self: *Dimension, entity_type: *const EntityType, position: Protocol.Vector3f) !*Entity {
        const entity = try self.allocator.create(Entity);
        entity.* = Entity.init(self.allocator, entity_type, self);
        entity.position = position;
        try self.entities.put(entity.runtime_id, entity);
        try self.broadcastAddEntity(entity);
        return entity;
    }

    pub fn removeEntity(self: *Dimension, entity: *Entity) !void {
        try self.broadcastRemoveEntity(entity);
        _ = self.entities.remove(entity.runtime_id);
        entity.deinit();
        self.allocator.destroy(entity);
    }

    fn broadcastAddEntity(self: *Dimension, entity: *Entity) !void {
        const BinaryStream = @import("BinaryStream").BinaryStream;
        var stream = BinaryStream.init(self.allocator, null, null);
        defer stream.deinit();

        const data = try entity.flags.buildDataItems(self.allocator);
        defer self.allocator.free(data);

        const packet = Protocol.AddEntityPacket{
            .uniqueEntityId = entity.unique_id,
            .runtimeEntityId = @bitCast(entity.runtime_id),
            .entityType = entity.entity_type.identifier,
            .position = entity.position,
            .pitch = entity.rotation.y,
            .yaw = entity.rotation.x,
            .headYaw = entity.head_yaw,
            .bodyYaw = entity.rotation.x,
            .entityMetadata = data,
            .entityProperties = Protocol.PropertySyncData.init(self.allocator),
        };

        const serialized = try packet.serialize(&stream);

        const conduit = self.world.conduit;
        const snapshots = conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            conduit.network.sendPacket(player.connection, serialized) catch {};
        }
    }

    fn broadcastRemoveEntity(self: *Dimension, entity: *Entity) !void {
        const BinaryStream = @import("BinaryStream").BinaryStream;
        var stream = BinaryStream.init(self.allocator, null, null);
        defer stream.deinit();

        const packet = Protocol.RemoveEntityPacket{
            .uniqueEntityId = entity.unique_id,
        };

        const serialized = try packet.serialize(&stream);

        const conduit = self.world.conduit;
        const snapshots = conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            conduit.network.sendPacket(player.connection, serialized) catch {};
        }
    }
};
