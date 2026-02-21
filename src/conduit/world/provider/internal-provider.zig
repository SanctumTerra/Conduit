const std = @import("std");
const WorldProvider = @import("./world-provider.zig").WorldProvider;
const Chunk = @import("../chunk/chunk.zig").Chunk;
const Dimension = @import("../dimension/dimension.zig").Dimension;
const chunkHash = @import("../dimension/dimension.zig").chunkHash;
const ChunkHash = @import("../dimension/dimension.zig").ChunkHash;

pub const InternalProvider = struct {
    allocator: std.mem.Allocator,
    chunks: std.AutoHashMap(*Dimension, std.AutoHashMap(ChunkHash, *Chunk)),
    buffers: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) !*InternalProvider {
        const self = try allocator.create(InternalProvider);
        self.* = InternalProvider{
            .allocator = allocator,
            .chunks = std.AutoHashMap(*Dimension, std.AutoHashMap(ChunkHash, *Chunk)).init(allocator),
            .buffers = std.StringHashMap([]const u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *InternalProvider) void {
        var chunk_iter = self.chunks.iterator();
        while (chunk_iter.next()) |entry| {
            var map = entry.value_ptr.*;
            var map_iter = map.valueIterator();
            while (map_iter.next()) |chunk| {
                chunk.*.deinit();
                self.allocator.destroy(chunk.*);
            }
            map.deinit();
        }
        self.chunks.deinit();

        var buf_iter = self.buffers.valueIterator();
        while (buf_iter.next()) |buf| {
            self.allocator.free(buf.*);
        }
        self.buffers.deinit();

        self.allocator.destroy(self);
    }

    pub fn readChunk(self: *InternalProvider, x: i32, z: i32, dimension: *Dimension) !*Chunk {
        const gop = try self.chunks.getOrPut(dimension);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.AutoHashMap(ChunkHash, *Chunk).init(self.allocator);
        }

        const hash = chunkHash(x, z);
        if (gop.value_ptr.get(hash)) |chunk| return chunk;

        const chunk = try self.allocator.create(Chunk);
        chunk.* = Chunk.init(self.allocator, x, z, dimension.dimension_type);
        try gop.value_ptr.put(hash, chunk);
        return chunk;
    }

    pub fn writeChunk(self: *InternalProvider, chunk: *Chunk, dimension: *Dimension) !void {
        const gop = try self.chunks.getOrPut(dimension);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.AutoHashMap(ChunkHash, *Chunk).init(self.allocator);
        }
        try gop.value_ptr.put(chunkHash(chunk.x, chunk.z), chunk);
    }

    pub fn readBuffer(self: *InternalProvider, key: []const u8) !?[]const u8 {
        return self.buffers.get(key);
    }

    pub fn writeBuffer(self: *InternalProvider, key: []const u8, buffer: []const u8) !void {
        if (self.buffers.get(key)) |old| {
            self.allocator.free(old);
        }
        const owned = try self.allocator.dupe(u8, buffer);
        try self.buffers.put(key, owned);
    }

    pub fn asProvider(self: *InternalProvider) WorldProvider {
        return WorldProvider{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = WorldProvider.VTable{
        .readChunk = vtableReadChunk,
        .writeChunk = vtableWriteChunk,
        .readBuffer = vtableReadBuffer,
        .writeBuffer = vtableWriteBuffer,
        .deinitFn = vtableDeinit,
    };

    fn vtableReadChunk(ptr: *anyopaque, x: i32, z: i32, dimension: *Dimension) anyerror!*Chunk {
        const self: *InternalProvider = @ptrCast(@alignCast(ptr));
        return self.readChunk(x, z, dimension);
    }

    fn vtableWriteChunk(ptr: *anyopaque, chunk: *Chunk, dimension: *Dimension) anyerror!void {
        const self: *InternalProvider = @ptrCast(@alignCast(ptr));
        return self.writeChunk(chunk, dimension);
    }

    fn vtableReadBuffer(ptr: *anyopaque, key: []const u8) anyerror!?[]const u8 {
        const self: *InternalProvider = @ptrCast(@alignCast(ptr));
        return self.readBuffer(key);
    }

    fn vtableWriteBuffer(ptr: *anyopaque, key: []const u8, buffer: []const u8) anyerror!void {
        const self: *InternalProvider = @ptrCast(@alignCast(ptr));
        return self.writeBuffer(key, buffer);
    }

    fn vtableDeinit(ptr: *anyopaque) void {
        const self: *InternalProvider = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
