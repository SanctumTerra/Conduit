const std = @import("std");
const Chunk = @import("../chunk/chunk.zig").Chunk;
const TerrainGenerator = @import("./terrain-generator.zig").TerrainGenerator;

const GenerationRequest = struct {
    x: i32,
    z: i32,
    allocator: std.mem.Allocator,
    generator: TerrainGenerator,
    result: ?*Chunk = null,
    err: bool = false,
    completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
};

pub const ThreadedGenerator = struct {
    allocator: std.mem.Allocator,
    generator: TerrainGenerator,
    pool: std.Thread.Pool,

    pub fn init(allocator: std.mem.Allocator, generator: TerrainGenerator, thread_count: ?usize) !*ThreadedGenerator {
        const self = try allocator.create(ThreadedGenerator);
        self.* = .{
            .allocator = allocator,
            .generator = generator,
            .pool = undefined,
        };
        try self.pool.init(.{
            .allocator = allocator,
            .n_jobs = thread_count,
        });
        return self;
    }

    pub fn deinit(self: *ThreadedGenerator) void {
        self.pool.deinit();
        self.generator.deinit();
        self.allocator.destroy(self);
    }

    pub fn generate(self: *ThreadedGenerator, x: i32, z: i32) !*Chunk {
        return self.generator.generate(self.allocator, x, z);
    }

    pub fn generateAsync(self: *ThreadedGenerator, x: i32, z: i32) !*Chunk {
        var request = GenerationRequest{
            .x = x,
            .z = z,
            .allocator = self.allocator,
            .generator = self.generator,
        };

        self.pool.spawn(runGeneration, .{&request});

        request.mutex.lock();
        defer request.mutex.unlock();
        while (!request.completed.load(.acquire)) {
            request.condition.wait(&request.mutex);
        }

        if (request.err) return error.GenerationFailed;
        return request.result.?;
    }

    fn runGeneration(request: *GenerationRequest) void {
        const chunk = request.generator.generate(request.allocator, request.x, request.z) catch {
            request.mutex.lock();
            request.err = true;
            request.completed.store(true, .release);
            request.condition.signal();
            request.mutex.unlock();
            return;
        };

        request.mutex.lock();
        request.result = chunk;
        request.completed.store(true, .release);
        request.condition.signal();
        request.mutex.unlock();
    }
};
