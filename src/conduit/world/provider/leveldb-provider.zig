const std = @import("std");
const LevelDB = @import("leveldb");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;
const ReadWriteOptions = NBT.ReadWriteOptions;
const Protocol = @import("protocol");
const WorldProvider = @import("./world-provider.zig").WorldProvider;
const Chunk = @import("../chunk/chunk.zig").Chunk;
const SubChunk = @import("../chunk/subchunk.zig").SubChunk;
const Dimension = @import("../dimension/dimension.zig").Dimension;
const chunkHash = @import("../dimension/dimension.zig").chunkHash;
const ChunkHash = @import("../dimension/dimension.zig").ChunkHash;
const chunk_mod = @import("../chunk/chunk.zig");
const serialization = @import("./serialization.zig");
const Entity = @import("../../entity/entity.zig").Entity;
const Player = @import("../../player/player.zig").Player;

const TAG_SUBCHUNK_PREFIX: u8 = 47;
const TAG_VERSION: u8 = 44;
const TAG_VERSION_OLD: u8 = 118;
const TAG_BLOCK_ENTITY: u8 = 49;

const trait_mod = @import("../block/traits/trait.zig");
const Block = @import("../block/block.zig").Block;
const BlockPermutation = @import("../block/block-permutation.zig").BlockPermutation;

pub const ChunkColumnData = struct {
    has_version: bool = false,
    subchunks: [chunk_mod.MAX_SUBCHUNKS]?[]const u8 = .{null} ** chunk_mod.MAX_SUBCHUNKS,
    block_entity_data: ?[]const u8 = null,

    pub fn deinit(self: *ChunkColumnData, allocator: std.mem.Allocator) void {
        for (&self.subchunks) |*sc| {
            if (sc.*) |data| {
                allocator.free(data);
                sc.* = null;
            }
        }
        if (self.block_entity_data) |d| allocator.free(d);
    }
};

pub const LevelDBProvider = struct {
    allocator: std.mem.Allocator,
    db: LevelDB.DB,
    chunks: std.AutoHashMap(*Dimension, std.AutoHashMap(ChunkHash, *Chunk)),

    pub fn init(allocator: std.mem.Allocator, path: [*:0]const u8) !*LevelDBProvider {
        const self = try allocator.create(LevelDBProvider);
        self.* = .{
            .allocator = allocator,
            .db = try LevelDB.DB.open(path, true),
            .chunks = std.AutoHashMap(*Dimension, std.AutoHashMap(ChunkHash, *Chunk)).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *LevelDBProvider) void {
        var chunk_iter = self.chunks.iterator();
        while (chunk_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.chunks.deinit();
        self.db.close();
        self.allocator.destroy(self);
    }

    pub fn readChunk(self: *LevelDBProvider, x: i32, z: i32, dimension: *Dimension) !*Chunk {
        const gop = try self.chunks.getOrPut(dimension);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.AutoHashMap(ChunkHash, *Chunk).init(self.allocator);
        }

        const hash = chunkHash(x, z);
        if (gop.value_ptr.get(hash)) |c| return c;

        const dim_index = dimensionIndex(dimension);
        const ver_key = versionKey(x, z, dim_index);
        const ver_data = self.db.get(ver_key.slice()) orelse blk: {
            const old_key = versionKeyOld(x, z, dim_index);
            break :blk self.db.get(old_key.slice()) orelse return error.ChunkNotFound;
        };
        LevelDB.DB.freeValue(ver_data);

        const chunk = try self.allocator.create(Chunk);
        chunk.* = Chunk.init(self.allocator, x, z, dimension.dimension_type);

        const offset = chunk_mod.yOffset(dimension.dimension_type);
        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            if (self.db.get(key.slice())) |data| {
                defer LevelDB.DB.freeValue(data);
                var stream = BinaryStream.init(self.allocator, data, null);
                const sc = try self.allocator.create(SubChunk);
                sc.* = SubChunk.deserialize(&stream, self.allocator) catch {
                    self.allocator.destroy(sc);
                    continue;
                };
                chunk.subchunks[i] = sc;
            }
        }

        try gop.value_ptr.put(hash, chunk);
        return chunk;
    }

    pub fn uncacheChunk(self: *LevelDBProvider, x: i32, z: i32, dimension: *Dimension) void {
        if (self.chunks.getPtr(dimension)) |dim_map| {
            _ = dim_map.remove(chunkHash(x, z));
        }
    }

    pub fn writeChunk(self: *LevelDBProvider, chunk: *Chunk, dimension: *Dimension) !void {
        const gop = try self.chunks.getOrPut(dimension);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.AutoHashMap(ChunkHash, *Chunk).init(self.allocator);
        }
        try gop.value_ptr.put(chunkHash(chunk.x, chunk.z), chunk);

        if (!chunk.dirty) return;

        const dim_index = dimensionIndex(dimension);
        const offset = chunk_mod.yOffset(dimension.dimension_type);

        var batch = try LevelDB.WriteBatch.init();
        defer batch.deinit();

        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            if (chunk.subchunks[i]) |sc| {
                if (sc.isEmpty()) continue;
                var stream = BinaryStream.init(self.allocator, null, null);
                defer stream.deinit();
                try sc.serializePersistence(&stream, self.allocator);
                const key = subchunkKey(chunk.x, chunk.z, @intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset))), dim_index);
                batch.put(key.slice(), stream.getBuffer());
            }
        }

        const ver_key = versionKey(chunk.x, chunk.z, dim_index);
        batch.put(ver_key.slice(), &[_]u8{40});

        try batch.write(&self.db);
        chunk.dirty = false;
    }

    pub fn saveAll(self: *LevelDBProvider) void {
        var batch = LevelDB.WriteBatch.init() catch return;
        defer batch.deinit();

        var dim_iter = self.chunks.iterator();
        while (dim_iter.next()) |dim_entry| {
            const dimension = dim_entry.key_ptr.*;
            const dim_index = dimensionIndex(dimension);
            const offset = chunk_mod.yOffset(dimension.dimension_type);
            var chunk_iter = dim_entry.value_ptr.valueIterator();
            while (chunk_iter.next()) |chunk_ptr| {
                const chunk = chunk_ptr.*;
                if (!chunk.dirty) continue;

                for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
                    if (chunk.subchunks[i]) |sc| {
                        if (sc.isEmpty()) continue;
                        var stream = BinaryStream.init(self.allocator, null, null);
                        defer stream.deinit();
                        sc.serializePersistence(&stream, self.allocator) catch continue;
                        const key = subchunkKey(chunk.x, chunk.z, @intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset))), dim_index);
                        batch.put(key.slice(), stream.getBuffer());
                    }
                }

                const ver_key = versionKey(chunk.x, chunk.z, dim_index);
                batch.put(ver_key.slice(), &[_]u8{40});
                chunk.dirty = false;
            }
        }

        batch.write(&self.db) catch {};
    }

    pub fn writePlayer(self: *LevelDBProvider, uuid: []const u8, player: *Player) !void {
        var tag = try serialization.serializePlayer(self.allocator, player);
        defer tag.deinit(self.allocator);
        const data = try serialization.encodeNbt(self.allocator, &tag);
        defer self.allocator.free(data);
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "player_server_{s}", .{uuid}) catch return;
        try self.db.put(key, data);
    }

    pub fn readPlayer(self: *LevelDBProvider, uuid: []const u8, player: *Player) !bool {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "player_server_{s}", .{uuid}) catch return false;
        const data = self.db.get(key) orelse return false;
        defer LevelDB.DB.freeValue(data);
        var tag = serialization.decodeNbt(self.allocator, data) catch return false;
        defer tag.deinit(self.allocator);
        serialization.deserializePlayer(self.allocator, player, &tag);
        return true;
    }

    pub fn writeChunkEntities(self: *LevelDBProvider, chunk: *Chunk, dimension: *Dimension) !void {
        const dim_index = dimensionIndex(dimension);
        var entities_in_chunk = std.ArrayList(i64){ .items = &.{}, .capacity = 0 };
        defer entities_in_chunk.deinit(self.allocator);

        var ent_iter = dimension.entities.valueIterator();
        while (ent_iter.next()) |entity_ptr| {
            const entity = entity_ptr.*;
            const ecx = @as(i32, @intFromFloat(@floor(entity.position.x))) >> 4;
            const ecz = @as(i32, @intFromFloat(@floor(entity.position.z))) >> 4;
            if (ecx == chunk.x and ecz == chunk.z) {
                var tag = serialization.serializeEntity(self.allocator, entity) catch continue;
                defer tag.deinit(self.allocator);
                const data = serialization.encodeNbt(self.allocator, &tag) catch continue;
                defer self.allocator.free(data);
                const actor_key = actorKey(entity.unique_id);
                self.db.put(actor_key.slice(), data) catch continue;
                try entities_in_chunk.append(self.allocator, entity.unique_id);
            }
        }

        const digp = digpKey(chunk.x, chunk.z, dim_index);
        if (entities_in_chunk.items.len > 0) {
            const digest_data = self.allocator.alloc(u8, entities_in_chunk.items.len * 8) catch return;
            defer self.allocator.free(digest_data);
            for (entities_in_chunk.items, 0..) |uid, i| {
                const bytes: [8]u8 = @bitCast(std.mem.nativeToLittle(i64, uid));
                @memcpy(digest_data[i * 8 .. (i + 1) * 8], &bytes);
            }
            try self.db.put(digp.slice(), digest_data);
        } else {
            self.db.delete(digp.slice()) catch {};
        }
    }

    pub fn readChunkEntities(self: *LevelDBProvider, chunk: *Chunk, dimension: *Dimension) !std.ArrayList(CompoundTag) {
        const dim_index = dimensionIndex(dimension);
        var result = std.ArrayList(CompoundTag){ .items = &.{}, .capacity = 0 };
        const digp = digpKey(chunk.x, chunk.z, dim_index);
        const digest_data = self.db.get(digp.slice()) orelse return result;
        defer LevelDB.DB.freeValue(digest_data);

        const count = digest_data.len / 8;
        for (0..count) |i| {
            const uid_bytes: *const [8]u8 = @ptrCast(digest_data[i * 8 .. (i + 1) * 8]);
            const uid = std.mem.littleToNative(i64, @bitCast(uid_bytes.*));
            const actor_k = actorKey(uid);
            const entity_data = self.db.get(actor_k.slice()) orelse continue;
            defer LevelDB.DB.freeValue(entity_data);
            const tag = serialization.decodeNbt(self.allocator, entity_data) catch continue;
            result.append(self.allocator, tag) catch {
                var t = tag;
                t.deinit(self.allocator);
                continue;
            };
        }
        return result;
    }

    pub fn writeBlockEntities(self: *LevelDBProvider, chunk: *Chunk, dimension: *Dimension) !void {
        const dim_index = dimensionIndex(dimension);
        const key = blockEntityKey(chunk.x, chunk.z, dim_index);

        const chunk_blocks = dimension.getBlocksInChunk(chunk.x, chunk.z);

        var tags = std.ArrayList(NBT.Tag){ .items = &.{}, .capacity = 0 };
        defer {
            for (tags.items) |*t| {
                switch (t.*) {
                    .Compound => |*c| c.deinit(self.allocator),
                    else => {},
                }
            }
            tags.deinit(self.allocator);
        }

        for (chunk_blocks) |block| {
            if (block.traits.items.len == 0) continue;

            var has_serialize = false;
            for (block.traits.items) |inst| {
                if (inst.vtable.onSerialize != null) {
                    has_serialize = true;
                    break;
                }
            }
            if (!has_serialize) continue;

            var tag = CompoundTag.init(self.allocator, null);
            tag.set("x", .{ .Int = NBT.IntTag.init(block.position.x, null) }) catch {
                tag.deinit(self.allocator);
                continue;
            };
            tag.set("y", .{ .Int = NBT.IntTag.init(block.position.y, null) }) catch {
                tag.deinit(self.allocator);
                continue;
            };
            tag.set("z", .{ .Int = NBT.IntTag.init(block.position.z, null) }) catch {
                tag.deinit(self.allocator);
                continue;
            };
            const id_str = self.allocator.dupe(u8, block.getIdentifier()) catch {
                tag.deinit(self.allocator);
                continue;
            };
            tag.set("id", .{ .String = NBT.StringTag.init(id_str, null) }) catch {
                tag.deinit(self.allocator);
                continue;
            };

            var trait_tags = std.ArrayList(NBT.Tag){ .items = &.{}, .capacity = 0 };
            defer trait_tags.deinit(self.allocator);
            for (block.traits.items) |instance| {
                const duped = self.allocator.dupe(u8, instance.identifier) catch continue;
                trait_tags.append(self.allocator, .{ .String = NBT.StringTag.init(duped, null) }) catch continue;
            }
            const trait_slice = trait_tags.toOwnedSlice(self.allocator) catch self.allocator.alloc(NBT.Tag, 0) catch &.{};
            tag.set("traits", .{ .List = NBT.ListTag.init(@constCast(trait_slice), null) }) catch {};

            block.fireEvent(.Serialize, .{&tag});

            tags.append(self.allocator, .{ .Compound = tag }) catch {
                tag.deinit(self.allocator);
                continue;
            };
        }

        if (tags.items.len == 0) {
            self.db.delete(key.slice()) catch {};
            return;
        }

        var stream = BinaryStream.init(self.allocator, null, null);
        defer stream.deinit();
        for (tags.items) |*t| {
            switch (t.*) {
                .Compound => |*c| CompoundTag.write(&stream, c, ReadWriteOptions.default) catch continue,
                else => {},
            }
        }
        try self.db.put(key.slice(), stream.getBuffer());
    }

    pub fn readBlockEntities(self: *LevelDBProvider, chunk: *Chunk, dimension: *Dimension) !void {
        const dim_index = dimensionIndex(dimension);
        const key = blockEntityKey(chunk.x, chunk.z, dim_index);
        const data = self.db.get(key.slice()) orelse {
            self.scanChunkForTraitBlocks(chunk, dimension);
            return;
        };
        defer LevelDB.DB.freeValue(data);

        var stream = BinaryStream.init(self.allocator, data, null);
        while (stream.offset < data.len) {
            var tag = CompoundTag.read(&stream, self.allocator, ReadWriteOptions.default) catch break;
            defer tag.deinit(self.allocator);

            const x = switch (tag.get("x") orelse continue) {
                .Int => |t| t.value,
                else => continue,
            };
            const y = switch (tag.get("y") orelse continue) {
                .Int => |t| t.value,
                else => continue,
            };
            const z = switch (tag.get("z") orelse continue) {
                .Int => |t| t.value,
                else => continue,
            };

            const pos = Protocol.BlockPosition{ .x = x, .y = y, .z = z };
            if (dimension.getBlockPtr(pos) != null) continue;

            const block = self.allocator.create(Block) catch continue;
            block.* = Block.init(self.allocator, dimension, pos);

            const traits_tag = tag.get("traits") orelse tag.get("Traits");
            if (traits_tag) |tt| {
                switch (tt) {
                    .List => |list| {
                        for (list.value) |item| {
                            switch (item) {
                                .String => |s| {
                                    if (trait_mod.getTraitFactory(s.value)) |f| {
                                        const instance = f(self.allocator) catch continue;
                                        block.addTrait(instance) catch continue;
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    else => {},
                }
            }

            if (block.traits.items.len == 0) {
                block.deinit();
                self.allocator.destroy(block);
                continue;
            }

            dimension.storeBlock(block) catch {
                block.deinit();
                self.allocator.destroy(block);
                continue;
            };

            block.fireEvent(.Deserialize, .{&tag});
        }

        self.scanChunkForTraitBlocks(chunk, dimension);
    }

    fn scanChunkForTraitBlocks(self: *LevelDBProvider, chunk: *Chunk, dimension: *Dimension) void {
        if (!trait_mod.hasAnyStaticTraits()) return;

        const offset = chunk_mod.yOffset(dimension.dimension_type);
        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            const sc = chunk.subchunks[i] orelse continue;
            if (sc.layers.items.len == 0) continue;
            const layer = &sc.layers.items[0];

            var trait_palette = std.AutoHashMap(u32, bool).init(self.allocator);
            defer trait_palette.deinit();

            for (layer.paletteSlice(), 0..) |network_id, pi| {
                const perm = BlockPermutation.getByNetworkId(network_id) orelse continue;
                if (std.mem.eql(u8, perm.identifier, "minecraft:air")) continue;
                if (trait_mod.hasRegisteredTraits(perm.identifier)) {
                    trait_palette.put(@intCast(pi), true) catch continue;
                }
            }

            if (trait_palette.count() == 0) continue;

            const sc_y: i32 = @as(i32, @intCast(i)) - @as(i32, @intCast(offset));
            for (0..4096) |pos_idx| {
                const palette_idx = layer.blocks[pos_idx];
                if (!trait_palette.contains(palette_idx)) continue;

                const bx: i32 = @intCast((pos_idx >> 8) & 0xf);
                const by: i32 = @intCast(pos_idx & 0xf);
                const bz: i32 = @intCast((pos_idx >> 4) & 0xf);

                const world_x = chunk.x * 16 + bx;
                const world_y = sc_y * 16 + by;
                const world_z = chunk.z * 16 + bz;

                const pos = Protocol.BlockPosition{ .x = world_x, .y = world_y, .z = world_z };
                if (dimension.getBlockPtr(pos) != null) continue;

                trait_mod.applyTraitsForBlock(self.allocator, dimension, pos) catch continue;
            }
        }
    }

    pub fn readBuffer(self: *LevelDBProvider, key: []const u8) !?[]const u8 {
        const val = self.db.get(key) orelse return null;
        const owned = try self.allocator.dupe(u8, val);
        LevelDB.DB.freeValue(val);
        return owned;
    }

    pub fn writeBuffer(self: *LevelDBProvider, key: []const u8, buffer: []const u8) !void {
        try self.db.put(key, buffer);
    }

    pub fn readChunkDirect(self: *LevelDBProvider, x: i32, z: i32, dim_type: @import("protocol").DimensionType) !*Chunk {
        const dim_index: i32 = switch (dim_type) {
            .Overworld => 0,
            .Nether => 1,
            .End => 2,
        };

        const ver_key = versionKey(x, z, dim_index);
        const ver_data = self.db.get(ver_key.slice()) orelse blk: {
            const old_key = versionKeyOld(x, z, dim_index);
            break :blk self.db.get(old_key.slice()) orelse return error.ChunkNotFound;
        };
        LevelDB.DB.freeValue(ver_data);

        const chunk = try self.allocator.create(Chunk);
        chunk.* = Chunk.init(self.allocator, x, z, dim_type);

        const offset = chunk_mod.yOffset(dim_type);
        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            if (self.db.get(key.slice())) |data| {
                defer LevelDB.DB.freeValue(data);
                var stream = BinaryStream.init(self.allocator, data, null);
                const sc = self.allocator.create(SubChunk) catch continue;
                sc.* = SubChunk.deserialize(&stream, self.allocator) catch {
                    self.allocator.destroy(sc);
                    continue;
                };
                chunk.subchunks[i] = sc;
            }
        }

        return chunk;
    }

    pub fn readChunkColumn(self: *LevelDBProvider, x: i32, z: i32, dim_type: Protocol.DimensionType, read_block_entities: bool) !ChunkColumnData {
        const allocator = self.allocator;
        const dim_index: i32 = switch (dim_type) {
            .Overworld => 0,
            .Nether => 1,
            .End => 2,
        };

        const base = chunkKeyBase(x, z, dim_index);
        var result = ChunkColumnData{};
        errdefer result.deinit(allocator);

        const offset = chunk_mod.yOffset(dim_type);
        var iter = self.db.iterator();
        defer iter.deinit();

        iter.seek(base.buf[0..base.len]);

        while (iter.valid()) {
            const k = iter.key();
            if (k.len < base.len or !std.mem.eql(u8, k[0..base.len], base.buf[0..base.len])) break;

            const tag_byte = k[base.len];

            if (tag_byte == TAG_VERSION or tag_byte == TAG_VERSION_OLD) {
                result.has_version = true;
            } else if (tag_byte == TAG_SUBCHUNK_PREFIX and k.len == base.len + 2) {
                const sc_index: i8 = @bitCast(k[base.len + 1]);
                const array_idx: i32 = @as(i32, sc_index) + @as(i32, @intCast(offset));
                if (array_idx >= 0 and array_idx < chunk_mod.MAX_SUBCHUNKS) {
                    const v = iter.value();
                    result.subchunks[@intCast(array_idx)] = try allocator.dupe(u8, v);
                }
            } else if (tag_byte == TAG_BLOCK_ENTITY and read_block_entities) {
                const v = iter.value();
                result.block_entity_data = try allocator.dupe(u8, v);
            }

            iter.next();
        }

        if (!result.has_version) {
            result.deinit(allocator);
            return error.ChunkNotFound;
        }

        return result;
    }

    pub fn asProvider(self: *LevelDBProvider) WorldProvider {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = WorldProvider.VTable{
        .readChunk = vtableReadChunk,
        .readChunkDirect = vtableReadChunkDirect,
        .writeChunk = vtableWriteChunk,
        .uncacheChunk = vtableUncacheChunk,
        .readBuffer = vtableReadBuffer,
        .writeBuffer = vtableWriteBuffer,
        .writePlayer = vtableWritePlayer,
        .readPlayer = vtableReadPlayer,
        .writeChunkEntities = vtableWriteChunkEntities,
        .writeBlockEntities = vtableWriteBlockEntities,
        .readBlockEntities = vtableReadBlockEntities,
        .deinitFn = vtableDeinit,
    };

    fn vtableReadChunk(ptr: *anyopaque, x: i32, z: i32, dimension: *Dimension) anyerror!*Chunk {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.readChunk(x, z, dimension);
    }

    fn vtableReadChunkDirect(ptr: *anyopaque, x: i32, z: i32, dim_type: @import("protocol").DimensionType) anyerror!*Chunk {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.readChunkDirect(x, z, dim_type);
    }

    fn vtableWriteChunk(ptr: *anyopaque, chunk: *Chunk, dimension: *Dimension) anyerror!void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.writeChunk(chunk, dimension);
    }

    fn vtableUncacheChunk(ptr: *anyopaque, x: i32, z: i32, dimension: *Dimension) void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        self.uncacheChunk(x, z, dimension);
    }

    fn vtableReadBuffer(ptr: *anyopaque, key: []const u8) anyerror!?[]const u8 {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.readBuffer(key);
    }

    fn vtableWriteBuffer(ptr: *anyopaque, key: []const u8, buffer: []const u8) anyerror!void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.writeBuffer(key, buffer);
    }

    fn vtableWritePlayer(ptr: *anyopaque, uuid: []const u8, player: *Player) anyerror!void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.writePlayer(uuid, player);
    }

    fn vtableReadPlayer(ptr: *anyopaque, uuid: []const u8, player: *Player) anyerror!bool {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.readPlayer(uuid, player);
    }

    fn vtableWriteChunkEntities(ptr: *anyopaque, chunk: *Chunk, dimension: *Dimension) anyerror!void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.writeChunkEntities(chunk, dimension);
    }

    fn vtableWriteBlockEntities(ptr: *anyopaque, chunk: *Chunk, dimension: *Dimension) anyerror!void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.writeBlockEntities(chunk, dimension);
    }

    fn vtableReadBlockEntities(ptr: *anyopaque, chunk: *Chunk, dimension: *Dimension) anyerror!void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        return self.readBlockEntities(chunk, dimension);
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *LevelDBProvider = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

fn dimensionIndex(dimension: *Dimension) i32 {
    return switch (dimension.dimension_type) {
        .Overworld => 0,
        .Nether => 1,
        .End => 2,
    };
}

fn chunkKeyBase(x: i32, z: i32, dim_index: i32) struct { buf: [12]u8, len: usize } {
    var buf: [12]u8 = undefined;
    @memcpy(buf[0..4], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, x))));
    @memcpy(buf[4..8], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, z))));
    if (dim_index != 0) {
        @memcpy(buf[8..12], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, dim_index))));
        return .{ .buf = buf, .len = 12 };
    }
    return .{ .buf = buf, .len = 8 };
}

const KeyBuf = struct {
    buf: [20]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const KeyBuf) []const u8 {
        return self.buf[0..self.len];
    }
};

fn subchunkKey(x: i32, z: i32, index: i8, dim_index: i32) KeyBuf {
    var key = KeyBuf{};
    const base = chunkKeyBase(x, z, dim_index);
    @memcpy(key.buf[0..base.len], base.buf[0..base.len]);
    key.buf[base.len] = TAG_SUBCHUNK_PREFIX;
    key.buf[base.len + 1] = @bitCast(index);
    key.len = base.len + 2;
    return key;
}

fn versionKey(x: i32, z: i32, dim_index: i32) KeyBuf {
    var key = KeyBuf{};
    const base = chunkKeyBase(x, z, dim_index);
    @memcpy(key.buf[0..base.len], base.buf[0..base.len]);
    key.buf[base.len] = TAG_VERSION;
    key.len = base.len + 1;
    return key;
}

fn versionKeyOld(x: i32, z: i32, dim_index: i32) KeyBuf {
    var key = KeyBuf{};
    const base = chunkKeyBase(x, z, dim_index);
    @memcpy(key.buf[0..base.len], base.buf[0..base.len]);
    key.buf[base.len] = TAG_VERSION_OLD;
    key.len = base.len + 1;
    return key;
}

fn blockEntityKey(x: i32, z: i32, dim_index: i32) KeyBuf {
    var key = KeyBuf{};
    const base = chunkKeyBase(x, z, dim_index);
    @memcpy(key.buf[0..base.len], base.buf[0..base.len]);
    key.buf[base.len] = TAG_BLOCK_ENTITY;
    key.len = base.len + 1;
    return key;
}

fn actorKey(unique_id: i64) KeyBuf {
    var key = KeyBuf{};
    @memcpy(key.buf[0..11], "actorprefix");
    @memcpy(key.buf[11..19], &@as([8]u8, @bitCast(std.mem.nativeToLittle(i64, unique_id))));
    key.len = 19;
    return key;
}

fn digpKey(x: i32, z: i32, dim_index: i32) KeyBuf {
    var key = KeyBuf{};
    @memcpy(key.buf[0..4], "digp");
    if (dim_index != 0) {
        @memcpy(key.buf[4..8], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, dim_index))));
        @memcpy(key.buf[8..12], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, x))));
        @memcpy(key.buf[12..16], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, z))));
        key.len = 16;
    } else {
        @memcpy(key.buf[4..8], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, x))));
        @memcpy(key.buf[8..12], &@as([4]u8, @bitCast(std.mem.nativeToLittle(i32, z))));
        key.len = 12;
    }
    return key;
}

test "WriteBatch chunk column round-trip" {
    var db = try LevelDB.DB.open("test_prop4_db\x00", true);
    defer {
        db.close();
        std.fs.cwd().deleteTree("test_prop4_db") catch {};
    }

    var rng = std.Random.DefaultPrng.init(0xdeadbeef);
    const random = rng.random();

    for (0..100) |iter| {
        const x: i32 = @intCast(@as(i32, @truncate(@as(i64, @intCast(iter)))) - 50);
        const z: i32 = @intCast(@as(i32, @truncate(@as(i64, @intCast(iter)))) + 10);
        const dim_index: i32 = 0;

        var batch = try LevelDB.WriteBatch.init();
        defer batch.deinit();

        const ver_key = versionKey(x, z, dim_index);
        batch.put(ver_key.slice(), &[_]u8{40});

        var expected_data: [chunk_mod.MAX_SUBCHUNKS]?[]u8 = .{null} ** chunk_mod.MAX_SUBCHUNKS;
        defer {
            for (&expected_data) |*d| {
                if (d.*) |data| std.testing.allocator.free(data);
            }
        }

        const num_subchunks = random.intRangeAtMost(usize, 1, 8);
        for (0..num_subchunks) |i| {
            const len = random.intRangeAtMost(usize, 4, 64);
            const data = try std.testing.allocator.alloc(u8, len);
            random.bytes(data);
            expected_data[i] = data;

            const sc_index: i8 = @intCast(@as(i32, @intCast(i)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            batch.put(key.slice(), data);
        }

        try batch.write(&db);

        const ver_read = db.get(ver_key.slice());
        try std.testing.expect(ver_read != null);
        LevelDB.DB.freeValue(ver_read.?);

        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            const read_val = db.get(key.slice());
            if (expected_data[i]) |expected| {
                try std.testing.expect(read_val != null);
                try std.testing.expectEqualSlices(u8, expected, read_val.?);
                LevelDB.DB.freeValue(read_val.?);
            } else {
                try std.testing.expect(read_val == null);
            }
        }

        var del_batch = try LevelDB.WriteBatch.init();
        defer del_batch.deinit();
        del_batch.delete(ver_key.slice());
        for (0..num_subchunks) |i| {
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            del_batch.delete(key.slice());
        }
        try del_batch.write(&db);
    }
}

test "WriteBatch saveAll multi-chunk persistence" {
    var db = try LevelDB.DB.open("test_prop6_db\x00", true);
    defer {
        db.close();
        std.fs.cwd().deleteTree("test_prop6_db") catch {};
    }

    var rng = std.Random.DefaultPrng.init(0xcafebabe);
    const random = rng.random();

    const N = 100;
    var keys: [N]KeyBuf = undefined;
    var values: [N][8]u8 = undefined;

    var batch = try LevelDB.WriteBatch.init();
    defer batch.deinit();

    for (0..N) |i| {
        const x: i32 = random.intRangeAtMost(i32, -1000, 1000);
        const z: i32 = random.intRangeAtMost(i32, -1000, 1000);
        keys[i] = versionKey(x, z, 0);
        random.bytes(&values[i]);
        batch.put(keys[i].slice(), &values[i]);
    }

    try batch.write(&db);

    for (0..N) |i| {
        const read_val = db.get(keys[i].slice());
        try std.testing.expect(read_val != null);
        try std.testing.expectEqualSlices(u8, &values[i], read_val.?);
        LevelDB.DB.freeValue(read_val.?);
    }
}

test "readChunkColumn skips block entities when flag is false" {
    var provider = try LevelDBProvider.init(std.testing.allocator, "test_prop5_db\x00");
    defer {
        provider.deinit();
        std.fs.cwd().deleteTree("test_prop5_db") catch {};
    }

    var rng = std.Random.DefaultPrng.init(0xfeed1234);
    const random = rng.random();

    for (0..100) |iter| {
        const x: i32 = @intCast(@as(i32, @truncate(@as(i64, @intCast(iter)))) - 50);
        const z: i32 = @intCast(@as(i32, @truncate(@as(i64, @intCast(iter)))) + 20);
        const dim_index: i32 = 0;

        var batch = try LevelDB.WriteBatch.init();
        defer batch.deinit();

        const ver_key = versionKey(x, z, dim_index);
        batch.put(ver_key.slice(), &[_]u8{40});

        const num_sc = random.intRangeAtMost(usize, 1, 4);
        var expected_sc: [chunk_mod.MAX_SUBCHUNKS]?[]u8 = .{null} ** chunk_mod.MAX_SUBCHUNKS;
        defer {
            for (&expected_sc) |*d| {
                if (d.*) |data| std.testing.allocator.free(data);
            }
        }

        for (0..num_sc) |i| {
            const len = random.intRangeAtMost(usize, 4, 32);
            const data = try std.testing.allocator.alloc(u8, len);
            random.bytes(data);
            expected_sc[i] = data;
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            batch.put(key.slice(), data);
        }

        var be_data: [16]u8 = undefined;
        random.bytes(&be_data);
        const be_key = blockEntityKey(x, z, dim_index);
        batch.put(be_key.slice(), &be_data);

        try batch.write(&provider.db);

        var col_skip = try provider.readChunkColumn(x, z, .Overworld, false);
        defer col_skip.deinit(std.testing.allocator);
        try std.testing.expect(col_skip.has_version);
        try std.testing.expect(col_skip.block_entity_data == null);
        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            if (expected_sc[i]) |expected| {
                try std.testing.expect(col_skip.subchunks[i] != null);
                try std.testing.expectEqualSlices(u8, expected, col_skip.subchunks[i].?);
            } else {
                try std.testing.expect(col_skip.subchunks[i] == null);
            }
        }

        var col_full = try provider.readChunkColumn(x, z, .Overworld, true);
        defer col_full.deinit(std.testing.allocator);
        try std.testing.expect(col_full.block_entity_data != null);
        try std.testing.expectEqualSlices(u8, &be_data, col_full.block_entity_data.?);

        var del_batch = try LevelDB.WriteBatch.init();
        defer del_batch.deinit();
        del_batch.delete(ver_key.slice());
        del_batch.delete(be_key.slice());
        for (0..num_sc) |i| {
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            del_batch.delete(key.slice());
        }
        try del_batch.write(&provider.db);
    }
}
