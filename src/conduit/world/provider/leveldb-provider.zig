const std = @import("std");
const LevelDB = @import("leveldb");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;
const ReadWriteOptions = NBT.ReadWriteOptions;
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
        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            if (chunk.subchunks[i]) |sc| {
                if (sc.isEmpty()) continue;
                var stream = BinaryStream.init(self.allocator, null, null);
                defer stream.deinit();
                try sc.serializePersistence(&stream, self.allocator);
                const key = subchunkKey(chunk.x, chunk.z, @intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset))), dim_index);
                try self.db.put(key.slice(), stream.getBuffer());
            }
        }

        const ver_key = versionKey(chunk.x, chunk.z, dim_index);
        try self.db.put(ver_key.slice(), &[_]u8{40});
        chunk.dirty = false;
    }

    pub fn saveAll(self: *LevelDBProvider) void {
        var dim_iter = self.chunks.iterator();
        while (dim_iter.next()) |dim_entry| {
            const dimension = dim_entry.key_ptr.*;
            var chunk_iter = dim_entry.value_ptr.valueIterator();
            while (chunk_iter.next()) |chunk_ptr| {
                const chunk = chunk_ptr.*;
                if (chunk.dirty) {
                    self.writeChunk(chunk, dimension) catch continue;
                }
            }
        }
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
        const read_opts = LevelDB.DB.createReadOptions() orelse return error.Failed;
        defer LevelDB.DB.destroyReadOptions(read_opts);

        const dim_index: i32 = switch (dim_type) {
            .Overworld => 0,
            .Nether => 1,
            .End => 2,
        };

        const ver_key = versionKey(x, z, dim_index);
        const ver_data = self.db.getWithOpts(ver_key.slice(), read_opts) orelse blk: {
            const old_key = versionKeyOld(x, z, dim_index);
            break :blk self.db.getWithOpts(old_key.slice(), read_opts) orelse return error.ChunkNotFound;
        };
        LevelDB.DB.freeValue(ver_data);

        const chunk = try self.allocator.create(Chunk);
        chunk.* = Chunk.init(self.allocator, x, z, dim_type);

        const offset = chunk_mod.yOffset(dim_type);
        for (0..chunk_mod.MAX_SUBCHUNKS) |i| {
            const sc_index: i8 = @intCast(@as(i32, @intCast(i)) - @as(i32, @intCast(offset)));
            const key = subchunkKey(x, z, sc_index, dim_index);
            if (self.db.getWithOpts(key.slice(), read_opts)) |data| {
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

        return chunk;
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
