const std = @import("std");
const Chunk = @import("../chunk/chunk.zig").Chunk;
const Dimension = @import("../dimension/dimension.zig").Dimension;
const ChunkHash = @import("../dimension/dimension.zig").ChunkHash;

pub const WorldProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        readChunk: *const fn (ptr: *anyopaque, x: i32, z: i32, dimension: *Dimension) anyerror!*Chunk,
        writeChunk: *const fn (ptr: *anyopaque, chunk: *Chunk, dimension: *Dimension) anyerror!void,
        readBuffer: *const fn (ptr: *anyopaque, key: []const u8) anyerror!?[]const u8,
        writeBuffer: *const fn (ptr: *anyopaque, key: []const u8, buffer: []const u8) anyerror!void,
        deinitFn: *const fn (ptr: *anyopaque) void,
    };

    pub fn readChunk(self: WorldProvider, x: i32, z: i32, dimension: *Dimension) !*Chunk {
        return self.vtable.readChunk(self.ptr, x, z, dimension);
    }

    pub fn writeChunk(self: WorldProvider, chunk: *Chunk, dimension: *Dimension) !void {
        return self.vtable.writeChunk(self.ptr, chunk, dimension);
    }

    pub fn readBuffer(self: WorldProvider, key: []const u8) !?[]const u8 {
        return self.vtable.readBuffer(self.ptr, key);
    }

    pub fn writeBuffer(self: WorldProvider, key: []const u8, buffer: []const u8) !void {
        return self.vtable.writeBuffer(self.ptr, key, buffer);
    }

    pub fn deinit(self: WorldProvider) void {
        self.vtable.deinitFn(self.ptr);
    }
};
