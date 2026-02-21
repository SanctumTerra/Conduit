const std = @import("std");
const Chunk = @import("../chunk/chunk.zig").Chunk;
const DimensionType = @import("protocol").DimensionType;

pub const GeneratorProperties = struct {
    seed: u64,
    dimension_type: DimensionType,

    pub fn init(seed: ?u64, dimension_type: DimensionType) GeneratorProperties {
        return .{
            .seed = seed orelse @intCast(@as(u64, @bitCast(std.time.timestamp()))),
            .dimension_type = dimension_type,
        };
    }
};

pub const TerrainGenerator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        generate: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, x: i32, z: i32) anyerror!*Chunk,
        deinitFn: *const fn (ptr: *anyopaque) void,
    };

    pub fn generate(self: TerrainGenerator, allocator: std.mem.Allocator, x: i32, z: i32) !*Chunk {
        return self.vtable.generate(self.ptr, allocator, x, z);
    }

    pub fn deinit(self: TerrainGenerator) void {
        self.vtable.deinitFn(self.ptr);
    }
};
