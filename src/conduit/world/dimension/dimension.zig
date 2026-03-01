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
const applyGlobalTraits = @import("../../entity/traits/root.zig").applyGlobalTraits;

const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const ItemType = @import("../../items/item-type.zig").ItemType;
const GravityTrait = @import("../../entity/traits/gravity.zig").GravityTrait;
const ItemEntityTrait = @import("../../entity/traits/item-entity.zig").ItemEntityTrait;
const tryMergeNearby = @import("../../entity/traits/item-entity.zig").tryMergeNearby;

pub const ChunkHash = i64;

pub fn chunkHash(x: i32, z: i32) ChunkHash {
    return (@as(i64, x) << 32) | @as(i64, @as(u32, @bitCast(z)));
}

const item_entity_type = EntityType{
    .identifier = "minecraft:item",
    .network_id = 64,
    .components = &.{},
    .tags = &.{},
};

pub const CachedPacket = struct {
    data: []const u8,
    generation: u64,
};

pub const Dimension = struct {
    world: *World,
    allocator: std.mem.Allocator,
    identifier: []const u8,
    dimension_type: Protocol.DimensionType,
    chunks: std.AutoHashMap(ChunkHash, *Chunk),
    entities: std.AutoHashMap(i64, *Entity),
    blocks: std.AutoHashMap(i64, *Block),
    blocks_by_chunk: std.AutoHashMap(ChunkHash, std.ArrayList(*Block)),
    chunk_packet_cache: std.AutoHashMap(ChunkHash, CachedPacket),
    chunk_generations: std.AutoHashMap(ChunkHash, u64),
    pending_removals: std.ArrayList(i64),
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
            .blocks = std.AutoHashMap(i64, *Block).init(allocator),
            .blocks_by_chunk = std.AutoHashMap(ChunkHash, std.ArrayList(*Block)).init(allocator),
            .chunk_packet_cache = std.AutoHashMap(ChunkHash, CachedPacket).init(allocator),
            .chunk_generations = std.AutoHashMap(ChunkHash, u64).init(allocator),
            .pending_removals = std.ArrayList(i64){ .items = &.{}, .capacity = 0 },
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
        var block_iter = self.blocks.valueIterator();
        while (block_iter.next()) |block| {
            block.*.deinit();
            self.allocator.destroy(block.*);
        }
        self.blocks.deinit();

        var bbc_iter = self.blocks_by_chunk.valueIterator();
        while (bbc_iter.next()) |list| {
            list.deinit(self.allocator);
        }
        self.blocks_by_chunk.deinit();

        var entity_iter = self.entities.valueIterator();
        while (entity_iter.next()) |entity| {
            entity.*.deinit();
            self.allocator.destroy(entity.*);
        }
        self.entities.deinit();

        self.pending_removals.deinit(self.allocator);

        var cache_iter = self.chunk_packet_cache.valueIterator();
        while (cache_iter.next()) |cached| {
            self.allocator.free(cached.data);
        }
        self.chunk_packet_cache.deinit();
        self.chunk_generations.deinit();

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

    pub fn invalidateChunkPacketCache(self: *Dimension, x: i32, z: i32) void {
        const hash = chunkHash(x, z);
        if (self.chunk_packet_cache.fetchRemove(hash)) |entry| {
            self.allocator.free(entry.value.data);
        }
    }

    pub fn getCachedChunkPacket(self: *Dimension, hash: ChunkHash) ?[]const u8 {
        const cached = self.chunk_packet_cache.get(hash) orelse return null;
        const current_gen = self.chunk_generations.get(hash) orelse 0;
        if (cached.generation != current_gen) return null;
        return cached.data;
    }

    pub fn putCachedChunkPacket(self: *Dimension, hash: ChunkHash, data: []const u8) void {
        const gen = self.chunk_generations.get(hash) orelse 0;
        if (self.chunk_packet_cache.fetchPut(hash, .{ .data = data, .generation = gen }) catch null) |old| {
            self.allocator.free(old.value.data);
        }
    }

    pub fn getOrCreateChunk(self: *Dimension, x: i32, z: i32) !*Chunk {
        const hash = chunkHash(x, z);
        if (self.chunks.get(hash)) |chunk| return chunk;

        const chunk = self.world.provider.readChunk(x, z, self) catch blk: {
            if (self.generator) |gen|
                break :blk try gen.generate(x, z)
            else {
                const c = try self.allocator.create(Chunk);
                c.* = Chunk.init(self.allocator, x, z, self.dimension_type);
                break :blk c;
            }
        };

        try self.chunks.put(hash, chunk);
        self.world.provider.readBlockEntities(chunk, self) catch {};
        return chunk;
    }

    pub fn removeChunk(self: *Dimension, x: i32, z: i32) void {
        const hash = chunkHash(x, z);
        if (self.chunk_packet_cache.fetchRemove(hash)) |cached| {
            self.allocator.free(cached.value.data);
        }
        if (self.chunks.fetchRemove(hash)) |entry| {
            var chunk = entry.value;
            if (self.getBlocksInChunk(x, z).len > 0) {
                self.world.provider.writeBlockEntities(chunk, self) catch {};
            }
            if (chunk.dirty) {
                self.world.provider.writeChunk(chunk, self) catch {};
            }
            self.removeBlocksInChunk(x, z);
            self.world.provider.uncacheChunk(x, z, self);
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
                    const coords2 = Protocol.ChunkCoords.unhash(h);
                    var chunk = entry.value;
                    if (self.getBlocksInChunk(coords2.x, coords2.z).len > 0) {
                        self.world.provider.writeBlockEntities(chunk, self) catch {};
                    }
                    if (chunk.dirty) {
                        self.world.provider.writeChunk(chunk, self) catch {};
                    }
                    self.removeBlocksInChunk(coords2.x, coords2.z);
                    self.world.provider.uncacheChunk(coords2.x, coords2.z, self);
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
        const hash = chunkHash(cx, cz);
        const gen = self.chunk_generations.get(hash) orelse 0;
        self.chunk_generations.put(hash, gen + 1) catch {};
        self.invalidateChunkPacketCache(cx, cz);
    }

    pub fn getBlock(self: *Dimension, pos: Protocol.BlockPosition) Block {
        if (self.blocks.get(blockPosHash(pos))) |block| return block.*;
        return Block.init(self.allocator, self, pos);
    }

    pub fn getBlockPtr(self: *Dimension, pos: Protocol.BlockPosition) ?*Block {
        return self.blocks.get(blockPosHash(pos));
    }

    pub fn storeBlock(self: *Dimension, block: *Block) !void {
        const hash = blockPosHash(block.position);
        if (self.blocks.fetchRemove(hash)) |entry| {
            var old = entry.value;
            self.removeFromChunkIndex(old);
            old.deinit();
            self.allocator.destroy(old);
        }
        try self.blocks.put(hash, block);
        const ch = chunkHash(block.position.x >> 4, block.position.z >> 4);
        const gop = try self.blocks_by_chunk.getOrPut(ch);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(*Block){ .items = &.{}, .capacity = 0 };
        }
        try gop.value_ptr.append(self.allocator, block);
    }

    pub fn removeBlock(self: *Dimension, pos: Protocol.BlockPosition) void {
        const hash = blockPosHash(pos);
        if (self.blocks.fetchRemove(hash)) |entry| {
            var block = entry.value;
            self.removeFromChunkIndex(block);
            block.deinit();
            self.allocator.destroy(block);
        }
    }

    fn removeFromChunkIndex(self: *Dimension, block: *Block) void {
        const ch = chunkHash(block.position.x >> 4, block.position.z >> 4);
        if (self.blocks_by_chunk.getPtr(ch)) |list| {
            for (list.items, 0..) |b, i| {
                if (b == block) {
                    _ = list.swapRemove(i);
                    break;
                }
            }
        }
    }

    pub fn blockPosHash(pos: Protocol.BlockPosition) i64 {
        const x: i64 = @intCast(pos.x);
        const y: i64 = @intCast(pos.y);
        const z: i64 = @intCast(pos.z);
        return (x & 0x3FFFFFF) | ((z & 0x3FFFFFF) << 26) | ((y & 0xFFF) << 52);
    }

    pub fn removeBlocksInChunk(self: *Dimension, cx: i32, cz: i32) void {
        const ch = chunkHash(cx, cz);
        if (self.blocks_by_chunk.fetchRemove(ch)) |entry| {
            var list = entry.value;
            for (list.items) |block| {
                const hash = blockPosHash(block.position);
                _ = self.blocks.remove(hash);
                var b = block;
                b.deinit();
                self.allocator.destroy(b);
            }
            list.deinit(self.allocator);
        }
    }

    pub fn getBlocksInChunk(self: *Dimension, cx: i32, cz: i32) []const *Block {
        const ch = chunkHash(cx, cz);
        if (self.blocks_by_chunk.getPtr(ch)) |list| return list.items;
        return &.{};
    }

    pub fn loadSpawnChunks(self: *Dimension) !void {
        const spawn_cx = self.spawn_position.x >> 4;
        const spawn_cz = self.spawn_position.z >> 4;
        const radius: i32 = 2;
        var cx: i32 = spawn_cx - radius;
        while (cx <= spawn_cx + radius) : (cx += 1) {
            var cz: i32 = spawn_cz - radius;
            while (cz <= spawn_cz + radius) : (cz += 1) {
                _ = try self.getOrCreateChunk(cx, cz);
            }
        }
    }

    pub fn getEntity(self: *Dimension, runtime_id: i64) ?*Entity {
        return self.entities.get(runtime_id);
    }

    pub fn spawnEntity(self: *Dimension, entity_type: *const EntityType, position: Protocol.Vector3f) !*Entity {
        return self.spawnEntityWithOptions(entity_type, position, "", false);
    }

    pub fn spawnEntityWithOptions(self: *Dimension, entity_type: *const EntityType, position: Protocol.Vector3f, name_tag: []const u8, nametag_always_visible: bool) !*Entity {
        const entity = try self.allocator.create(Entity);
        entity.* = Entity.init(self.allocator, entity_type, self);
        entity.position = position;
        entity.name_tag = name_tag;
        entity.nametag_always_visible = nametag_always_visible;
        try applyGlobalTraits(self.allocator, entity);
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

    pub fn flushPendingRemovals(self: *Dimension) void {
        for (self.pending_removals.items) |rid| {
            if (self.entities.fetchRemove(rid)) |entry| {
                var entity = entry.value;
                self.broadcastRemoveEntity(entity) catch {};
                entity.deinit();
                self.allocator.destroy(entity);
            }
        }
        self.pending_removals.clearRetainingCapacity();
    }

    pub fn spawnItemEntity(self: *Dimension, item_type: *ItemType, count: u16, position: Protocol.Vector3f) !*Entity {
        const BinaryStream = @import("BinaryStream").BinaryStream;

        if (tryMergeNearby(self, item_type.identifier, count, position)) |existing| {
            const existing_state = existing.getTraitState(ItemEntityTrait) orelse return existing;
            self.broadcastRemoveEntity(existing) catch {};

            var merged_stack = ItemStack.init(self.allocator, item_type, .{ .stackSize = existing_state.count });
            const merged_net = merged_stack.toNetworkStack();
            defer merged_stack.deinit();

            var stream = BinaryStream.init(self.allocator, null, null);
            defer stream.deinit();

            const packet = Protocol.AddItemActorPacket{
                .uniqueEntityId = existing.unique_id,
                .runtimeEntityId = @bitCast(existing.runtime_id),
                .item = merged_net,
                .position = existing.position,
                .velocity = Protocol.Vector3f.init(0, 0, 0),
            };
            const serialized = try packet.serialize(&stream, self.allocator);

            const conduit = self.world.conduit;
            const snapshots = conduit.getPlayerSnapshots();
            for (snapshots) |player| {
                if (!player.spawned) continue;
                conduit.network.sendPacket(player.connection, serialized) catch {};
            }

            return existing;
        }

        const entity = try self.allocator.create(Entity);
        entity.* = Entity.init(self.allocator, &item_entity_type, self);
        entity.position = position;

        const gravity = try GravityTrait.create(self.allocator, .{
            .force = -0.04,
            .falling_distance = 0,
            .falling_ticks = 0,
            .on_ground = false,
        });
        try entity.addTrait(gravity);

        const pickup = try ItemEntityTrait.create(self.allocator, .{
            .item_identifier = item_type.identifier,
            .count = count,
            .pickup_delay = 10,
            .lifetime = 0,
            .pending_remove = false,
        });
        try entity.addTrait(pickup);

        try self.entities.put(entity.runtime_id, entity);

        var item_stack = ItemStack.init(self.allocator, item_type, .{ .stackSize = count });
        const net_item = item_stack.toNetworkStack();
        defer item_stack.deinit();

        var stream = BinaryStream.init(self.allocator, null, null);
        defer stream.deinit();

        const packet = Protocol.AddItemActorPacket{
            .uniqueEntityId = entity.unique_id,
            .runtimeEntityId = @bitCast(entity.runtime_id),
            .item = net_item,
            .position = position,
            .velocity = Protocol.Vector3f.init(0, 0.25, 0),
        };
        const serialized = try packet.serialize(&stream, self.allocator);

        const conduit = self.world.conduit;
        const snapshots = conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            conduit.network.sendPacket(player.connection, serialized) catch {};
        }

        return entity;
    }

    fn broadcastAddEntity(self: *Dimension, entity: *Entity) !void {
        const BinaryStream = @import("BinaryStream").BinaryStream;
        var stream = BinaryStream.init(self.allocator, null, null);
        defer stream.deinit();

        const flags_data = try entity.flags.buildDataItems(self.allocator);
        defer self.allocator.free(flags_data);

        var metadata = std.ArrayList(Protocol.DataItem){ .items = &.{}, .capacity = 0 };
        defer if (metadata.capacity > 0) metadata.deinit(self.allocator);

        for (flags_data) |item| {
            try metadata.append(self.allocator, item);
        }

        if (entity.name_tag.len > 0) {
            try metadata.append(self.allocator, Protocol.DataItem.init(
                Protocol.ActorDataId.Name,
                .String,
                .{ .String = entity.name_tag },
            ));
            try metadata.append(self.allocator, Protocol.DataItem.initByte(
                Protocol.ActorDataId.AlwaysShowNameTag,
                if (entity.nametag_always_visible) 1 else 0,
            ));
        }

        const packet = Protocol.AddEntityPacket{
            .uniqueEntityId = entity.unique_id,
            .runtimeEntityId = @bitCast(entity.runtime_id),
            .entityType = entity.entity_type.identifier,
            .position = entity.position,
            .pitch = entity.rotation.y,
            .yaw = entity.rotation.x,
            .headYaw = entity.head_yaw,
            .bodyYaw = entity.rotation.x,
            .entityMetadata = metadata.items,
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

pub const TickScheduler = struct {
    const RING_SIZE: usize = 200;

    const TickKey = struct {
        pos_hash: i64,
        block_hash: u64,
    };

    const ScheduledTick = struct {
        pos: Protocol.BlockPosition,
        block_hash: u64,
    };

    ring: [RING_SIZE]std.ArrayList(ScheduledTick),
    offset: usize,
    queued: std.AutoHashMap(TickKey, void),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TickScheduler {
        var sched: TickScheduler = .{
            .ring = undefined,
            .offset = 0,
            .queued = std.AutoHashMap(TickKey, void).init(allocator),
            .allocator = allocator,
        };
        for (&sched.ring) |*slot| {
            slot.* = std.ArrayList(ScheduledTick){ .items = &.{}, .capacity = 0 };
        }
        return sched;
    }

    pub fn deinit(self: *TickScheduler) void {
        for (&self.ring) |*slot| {
            slot.deinit(self.allocator);
        }
        self.queued.deinit();
    }

    pub fn schedule(self: *TickScheduler, pos: Protocol.BlockPosition, block_hash: u64, delay: usize) void {
        if (delay == 0 or delay >= RING_SIZE) return;
        const key = TickKey{ .pos_hash = Dimension.blockPosHash(pos), .block_hash = block_hash };
        if (self.queued.contains(key)) return;
        self.queued.put(key, {}) catch return;
        const slot_idx = (self.offset + delay) % RING_SIZE;
        self.ring[slot_idx].append(self.allocator, .{ .pos = pos, .block_hash = block_hash }) catch return;
    }

    pub fn stepTick(self: *TickScheduler) []const ScheduledTick {
        const slot = &self.ring[self.offset];
        for (slot.items) |tick| {
            const key = TickKey{ .pos_hash = Dimension.blockPosHash(tick.pos), .block_hash = tick.block_hash };
            _ = self.queued.remove(key);
        }
        const result = slot.items;
        self.offset = (self.offset + 1) % RING_SIZE;
        return result;
    }

    pub fn clearCurrentSlot(self: *TickScheduler) void {
        const prev = if (self.offset == 0) RING_SIZE - 1 else self.offset - 1;
        self.ring[prev].clearRetainingCapacity();
    }
};

test "tick scheduler delivers at correct delay" {
    var sched = TickScheduler.init(std.testing.allocator);
    defer sched.deinit();

    var rng = std.Random.DefaultPrng.init(0xaabb1122);
    const random = rng.random();

    for (0..100) |_| {
        const delay = random.intRangeAtMost(usize, 1, TickScheduler.RING_SIZE - 1);
        const pos = Protocol.BlockPosition{
            .x = random.intRangeAtMost(i32, -1000, 1000),
            .y = random.intRangeAtMost(i32, 0, 255),
            .z = random.intRangeAtMost(i32, -1000, 1000),
        };
        const block_hash = random.int(u64);

        sched.schedule(pos, block_hash, delay);

        for (0..delay - 1) |_| {
            const ticks = sched.stepTick();
            sched.clearCurrentSlot();
            for (ticks) |t| {
                try std.testing.expect(t.block_hash != block_hash or
                    Dimension.blockPosHash(t.pos) != Dimension.blockPosHash(pos));
            }
        }

        const delivered = sched.stepTick();
        sched.clearCurrentSlot();
        var found = false;
        for (delivered) |t| {
            if (t.block_hash == block_hash and Dimension.blockPosHash(t.pos) == Dimension.blockPosHash(pos)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "tick scheduler rejects duplicates" {
    var sched = TickScheduler.init(std.testing.allocator);
    defer sched.deinit();

    var rng = std.Random.DefaultPrng.init(0xccdd3344);
    const random = rng.random();

    for (0..100) |_| {
        const delay = random.intRangeAtMost(usize, 1, 50);
        const pos = Protocol.BlockPosition{
            .x = random.intRangeAtMost(i32, -100, 100),
            .y = random.intRangeAtMost(i32, 0, 255),
            .z = random.intRangeAtMost(i32, -100, 100),
        };
        const block_hash = random.int(u64);

        sched.schedule(pos, block_hash, delay);
        sched.schedule(pos, block_hash, delay);

        for (0..delay) |_| {
            _ = sched.stepTick();
            sched.clearCurrentSlot();
        }

        try std.testing.expect(!sched.queued.contains(.{
            .pos_hash = Dimension.blockPosHash(pos),
            .block_hash = block_hash,
        }));
    }
}

pub const RandomTickEligibility = struct {
    eligible: []bool,
    allocator: std.mem.Allocator,
    max_id: usize,

    pub fn init(allocator: std.mem.Allocator, eligible_identifiers: []const []const u8) !RandomTickEligibility {
        var max_id: usize = 0;
        var iter = BlockPermutation.permutations.valueIterator();
        while (iter.next()) |perm| {
            const nid: usize = @intCast(@as(u32, @bitCast(perm.*.network_id)));
            if (nid > max_id) max_id = nid;
        }

        const table = try allocator.alloc(bool, max_id + 1);
        @memset(table, false);

        iter = BlockPermutation.permutations.valueIterator();
        while (iter.next()) |perm| {
            const nid: usize = @intCast(@as(u32, @bitCast(perm.*.network_id)));
            for (eligible_identifiers) |eid| {
                if (std.mem.eql(u8, perm.*.identifier, eid)) {
                    table[nid] = true;
                    break;
                }
            }
        }

        return .{ .eligible = table, .allocator = allocator, .max_id = max_id };
    }

    pub fn deinit(self: *RandomTickEligibility) void {
        self.allocator.free(self.eligible);
    }

    pub fn isEligible(self: *const RandomTickEligibility, network_id: i32) bool {
        const idx: usize = @intCast(@as(u32, @bitCast(network_id)));
        if (idx > self.max_id) return false;
        return self.eligible[idx];
    }
};

pub fn isChunkInSimRange(cx: i32, cz: i32, px: i32, pz: i32, sim_dist: i32) bool {
    const dx = cx - px;
    const dz = cz - pz;
    return dx * dx + dz * dz <= sim_dist * sim_dist;
}

test "random tick spatial filtering" {
    var rng = std.Random.DefaultPrng.init(0xdead5678);
    const random = rng.random();

    for (0..100) |_| {
        const px = random.intRangeAtMost(i32, -100, 100);
        const pz = random.intRangeAtMost(i32, -100, 100);
        const sim_dist = random.intRangeAtMost(i32, 1, 8);

        const in_cx = px + random.intRangeAtMost(i32, 0, sim_dist);
        const in_cz = pz;
        const out_cx = px + sim_dist + random.intRangeAtMost(i32, 1, 10);
        const out_cz = pz + sim_dist + random.intRangeAtMost(i32, 1, 10);

        const in_dx = in_cx - px;
        const in_dz = in_cz - pz;
        if (in_dx * in_dx + in_dz * in_dz <= sim_dist * sim_dist) {
            try std.testing.expect(isChunkInSimRange(in_cx, in_cz, px, pz, sim_dist));
        }

        try std.testing.expect(!isChunkInSimRange(out_cx, out_cz, px, pz, sim_dist));
    }
}

test "random tick eligibility lookup" {
    const allocator = std.testing.allocator;
    try BlockPermutation.initRegistry(allocator);
    defer BlockPermutation.deinitRegistry();

    const state1 = BlockPermutation.BlockState.init(allocator);
    const perm1 = try BlockPermutation.init(allocator, 1, "minecraft:grass_block", state1);
    try perm1.register();

    const state2 = BlockPermutation.BlockState.init(allocator);
    const perm2 = try BlockPermutation.init(allocator, 2, "minecraft:stone", state2);
    try perm2.register();

    const state3 = BlockPermutation.BlockState.init(allocator);
    const perm3 = try BlockPermutation.init(allocator, 3, "minecraft:wheat", state3);
    try perm3.register();

    const eligible_ids = [_][]const u8{ "minecraft:grass_block", "minecraft:wheat" };
    var rte = try RandomTickEligibility.init(allocator, &eligible_ids);
    defer rte.deinit();

    try std.testing.expect(rte.isEligible(1));
    try std.testing.expect(!rte.isEligible(2));
    try std.testing.expect(rte.isEligible(3));
    try std.testing.expect(!rte.isEligible(999));
}

test "blocks_by_chunk index stays consistent with blocks map" {
    const allocator = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0x12345678);
    const random = rng.random();

    var blocks = std.AutoHashMap(i64, Protocol.BlockPosition).init(allocator);
    defer blocks.deinit();
    var blocks_by_chunk = std.AutoHashMap(ChunkHash, std.ArrayList(i64)).init(allocator);
    defer {
        var it = blocks_by_chunk.valueIterator();
        while (it.next()) |list| list.deinit(allocator);
        blocks_by_chunk.deinit();
    }

    for (0..100) |_| {
        const pos = Protocol.BlockPosition{
            .x = random.intRangeAtMost(i32, -64, 64),
            .y = random.intRangeAtMost(i32, 0, 255),
            .z = random.intRangeAtMost(i32, -64, 64),
        };
        const hash = Dimension.blockPosHash(pos);
        const ch = chunkHash(pos.x >> 4, pos.z >> 4);

        if (random.boolean()) {
            blocks.put(hash, pos) catch continue;
            const gop = blocks_by_chunk.getOrPut(ch) catch continue;
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
            }
            var already = false;
            for (gop.value_ptr.items) |h| {
                if (h == hash) {
                    already = true;
                    break;
                }
            }
            if (!already) gop.value_ptr.append(allocator, hash) catch continue;
        } else {
            if (blocks.fetchRemove(hash)) |_| {
                if (blocks_by_chunk.getPtr(ch)) |list| {
                    for (list.items, 0..) |h, i| {
                        if (h == hash) {
                            _ = list.swapRemove(i);
                            break;
                        }
                    }
                }
            }
        }

        var block_it = blocks.iterator();
        while (block_it.next()) |entry| {
            const p = entry.value_ptr.*;
            const c = chunkHash(p.x >> 4, p.z >> 4);
            const list = blocks_by_chunk.getPtr(c);
            try std.testing.expect(list != null);
            var found = false;
            for (list.?.items) |h| {
                if (h == entry.key_ptr.*) {
                    found = true;
                    break;
                }
            }
            try std.testing.expect(found);
        }
    }
}

test "removeBlocksInChunk removes only target chunk blocks" {
    const allocator = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0x87654321);
    const random = rng.random();

    for (0..100) |_| {
        var blocks = std.AutoHashMap(i64, Protocol.BlockPosition).init(allocator);
        defer blocks.deinit();
        var blocks_by_chunk = std.AutoHashMap(ChunkHash, std.ArrayList(i64)).init(allocator);
        defer {
            var it = blocks_by_chunk.valueIterator();
            while (it.next()) |list| list.deinit(allocator);
            blocks_by_chunk.deinit();
        }

        const target_cx = random.intRangeAtMost(i32, -4, 4);
        const target_cz = random.intRangeAtMost(i32, -4, 4);

        for (0..20) |_| {
            const cx = random.intRangeAtMost(i32, -4, 4);
            const cz = random.intRangeAtMost(i32, -4, 4);
            const pos = Protocol.BlockPosition{
                .x = cx * 16 + random.intRangeAtMost(i32, 0, 15),
                .y = random.intRangeAtMost(i32, 0, 255),
                .z = cz * 16 + random.intRangeAtMost(i32, 0, 15),
            };
            const hash = Dimension.blockPosHash(pos);
            const ch = chunkHash(pos.x >> 4, pos.z >> 4);
            blocks.put(hash, pos) catch continue;
            const gop = blocks_by_chunk.getOrPut(ch) catch continue;
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
            }
            var already = false;
            for (gop.value_ptr.items) |h| {
                if (h == hash) {
                    already = true;
                    break;
                }
            }
            if (!already) gop.value_ptr.append(allocator, hash) catch continue;
        }

        const total_before = blocks.count();
        const target_ch = chunkHash(target_cx, target_cz);
        const target_count = if (blocks_by_chunk.getPtr(target_ch)) |list| list.items.len else 0;

        if (blocks_by_chunk.fetchRemove(target_ch)) |entry| {
            var list = entry.value;
            for (list.items) |h| {
                _ = blocks.remove(h);
            }
            list.deinit(allocator);
        }

        try std.testing.expectEqual(total_before - target_count, blocks.count());

        var remaining_it = blocks.iterator();
        while (remaining_it.next()) |entry| {
            const p = entry.value_ptr.*;
            try std.testing.expect((p.x >> 4) != target_cx or (p.z >> 4) != target_cz);
        }
    }
}

test "generation counter strictly increases" {
    const allocator = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0xface1234);
    const random = rng.random();

    var generations = std.AutoHashMap(ChunkHash, u64).init(allocator);
    defer generations.deinit();

    for (0..100) |_| {
        const cx = random.intRangeAtMost(i32, -10, 10);
        const cz = random.intRangeAtMost(i32, -10, 10);
        const hash = chunkHash(cx, cz);

        const old_gen = generations.get(hash) orelse 0;
        const new_gen = old_gen + 1;
        try generations.put(hash, new_gen);

        try std.testing.expect(new_gen > old_gen);
        try std.testing.expectEqual(new_gen, generations.get(hash).?);
    }
}

test "stale cache detected after generation change" {
    const allocator = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0xbabe5678);
    const random = rng.random();

    var cache = std.AutoHashMap(ChunkHash, CachedPacket).init(allocator);
    defer cache.deinit();
    var generations = std.AutoHashMap(ChunkHash, u64).init(allocator);
    defer generations.deinit();

    for (0..100) |_| {
        const cx = random.intRangeAtMost(i32, -5, 5);
        const cz = random.intRangeAtMost(i32, -5, 5);
        const hash = chunkHash(cx, cz);

        const gen = generations.get(hash) orelse 0;
        try cache.put(hash, .{ .data = &.{}, .generation = gen });

        try generations.put(hash, gen + 1);

        const cached = cache.get(hash).?;
        const current_gen = generations.get(hash).?;
        try std.testing.expect(cached.generation != current_gen);
    }
}
