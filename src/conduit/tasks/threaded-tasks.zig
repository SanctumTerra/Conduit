const std = @import("std");

pub const WorkFn = *const fn (ctx: *anyopaque) void;
pub const CallbackFn = *const fn (ctx: *anyopaque) void;
pub const CleanupFn = *const fn (ctx: *anyopaque) void;

pub const ThreadedTask = struct {
    work: WorkFn,
    callback: ?CallbackFn = null,
    cleanup: ?CleanupFn = null,
    ctx: *anyopaque,
};

pub const WorkerCountResolution = struct {
    cpu_count: usize,
    recommended_max: usize,
    requested_count: usize,
    resolved_count: usize,
    auto_selected: bool,
};

pub fn computeWorkerCount(configured_count: usize) usize {
    return resolveWorkerCount(configured_count).resolved_count;
}

pub fn totalServerThreadCount(worker_count: usize) usize {
    return 1 + 2 + worker_count;
}

pub fn resolveWorkerCount(configured_count: usize) WorkerCountResolution {
    const cpu_count = std.Thread.getCpuCount() catch 4;
    return resolveWorkerCountForCpu(configured_count, cpu_count);
}

fn resolveWorkerCountForCpu(configured_count: usize, cpu_count: usize) WorkerCountResolution {
    const recommended_max = recommendedWorkerCountForCpu(cpu_count);
    if (configured_count > 0) {
        return .{
            .cpu_count = cpu_count,
            .recommended_max = recommended_max,
            .requested_count = configured_count,
            .resolved_count = @min(configured_count, recommended_max),
            .auto_selected = false,
        };
    }

    return .{
        .cpu_count = cpu_count,
        .recommended_max = recommended_max,
        .requested_count = 0,
        .resolved_count = recommended_max,
        .auto_selected = true,
    };
}

fn recommendedWorkerCountForCpu(cpu_count: usize) usize {
    if (cpu_count <= 2) return 1;
    const count = cpu_count - 2;
    return @max(@as(usize, 1), @min(count, 16));
}

pub const ThreadedTaskQueue = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(ThreadedTask),
    completed: std.ArrayList(ThreadedTask),
    pending_mutex: std.Thread.Mutex,
    pending_cond: std.Thread.Condition,
    completed_mutex: std.Thread.Mutex,
    workers: []?std.Thread,
    running: bool,
    configured_worker_count: usize,
    detected_cpu_count: usize,
    active_worker_count: usize,

    pub fn init(allocator: std.mem.Allocator, configured_worker_count: usize) ThreadedTaskQueue {
        return .{
            .allocator = allocator,
            .pending = std.ArrayList(ThreadedTask){ .items = &.{}, .capacity = 0 },
            .completed = std.ArrayList(ThreadedTask){ .items = &.{}, .capacity = 0 },
            .pending_mutex = .{},
            .pending_cond = .{},
            .completed_mutex = .{},
            .workers = &.{},
            .running = false,
            .configured_worker_count = configured_worker_count,
            .detected_cpu_count = 0,
            .active_worker_count = 0,
        };
    }

    pub fn start(self: *ThreadedTaskQueue) !void {
        self.running = true;
        const resolution = resolveWorkerCount(self.configured_worker_count);
        self.detected_cpu_count = resolution.cpu_count;
        self.active_worker_count = resolution.resolved_count;
        const worker_count = resolution.resolved_count;
        self.workers = try self.allocator.alloc(?std.Thread, worker_count);
        for (self.workers) |*w| {
            w.* = try std.Thread.spawn(.{}, workerLoop, .{self});
        }
    }

    pub fn workerCount(self: *const ThreadedTaskQueue) usize {
        return self.active_worker_count;
    }

    pub fn detectedCpuCount(self: *const ThreadedTaskQueue) usize {
        return self.detected_cpu_count;
    }

    pub fn enqueue(self: *ThreadedTaskQueue, task: ThreadedTask) !void {
        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();
        try self.pending.append(self.allocator, task);
        self.pending_cond.signal();
    }

    pub fn drainCompleted(self: *ThreadedTaskQueue, budget_ns: u64) void {
        const drain_start = std.time.nanoTimestamp();
        while (true) {
            self.completed_mutex.lock();
            if (self.completed.items.len == 0) {
                self.completed_mutex.unlock();
                return;
            }
            const task = self.completed.swapRemove(0);
            self.completed_mutex.unlock();

            if (task.callback) |cb| cb(task.ctx);

            const elapsed: u64 = @intCast(@max(0, std.time.nanoTimestamp() - drain_start));
            if (elapsed >= budget_ns) return;
        }
    }

    pub fn clearPending(self: *ThreadedTaskQueue) void {
        self.pending_mutex.lock();
        for (self.pending.items) |task| {
            if (task.cleanup) |c_fn| c_fn(task.ctx);
        }
        self.pending.clearRetainingCapacity();
        self.pending_mutex.unlock();
    }

    pub fn stop(self: *ThreadedTaskQueue) void {
        self.pending_mutex.lock();
        self.running = false;
        self.pending_cond.broadcast();
        self.pending_mutex.unlock();

        for (self.workers) |*w| {
            if (w.*) |t| {
                t.join();
                w.* = null;
            }
        }
    }

    pub fn deinit(self: *ThreadedTaskQueue) void {
        self.stop();
        for (self.pending.items) |task| {
            if (task.cleanup) |c_fn| c_fn(task.ctx);
        }
        if (self.pending.capacity > 0) self.pending.deinit(self.allocator);
        for (self.completed.items) |task| {
            if (task.cleanup) |c_fn| c_fn(task.ctx);
        }
        if (self.completed.capacity > 0) self.completed.deinit(self.allocator);
        if (self.workers.len > 0) self.allocator.free(self.workers);
    }

    fn workerLoop(self: *ThreadedTaskQueue) void {
        while (true) {
            self.pending_mutex.lock();
            while (self.pending.items.len == 0 and self.running) {
                self.pending_cond.wait(&self.pending_mutex);
            }
            if (!self.running and self.pending.items.len == 0) {
                self.pending_mutex.unlock();
                return;
            }
            const task = self.pending.swapRemove(0);
            self.pending_mutex.unlock();

            task.work(task.ctx);

            self.completed_mutex.lock();
            self.completed.append(self.allocator, task) catch {
                if (task.cleanup) |c_fn| c_fn(task.ctx);
            };
            self.completed_mutex.unlock();
        }
    }
};

test "dynamic worker count bounds" {
    try std.testing.expectEqual(@as(usize, 1), resolveWorkerCountForCpu(0, 2).resolved_count);
    try std.testing.expectEqual(@as(usize, 6), resolveWorkerCountForCpu(0, 8).resolved_count);
    try std.testing.expectEqual(@as(usize, 16), resolveWorkerCountForCpu(0, 32).resolved_count);
}

test "configured worker count is respected" {
    try std.testing.expectEqual(@as(usize, 4), resolveWorkerCountForCpu(4, 8).resolved_count);
    try std.testing.expectEqual(@as(usize, 6), resolveWorkerCountForCpu(128, 8).resolved_count);
    try std.testing.expectEqual(@as(usize, 1), resolveWorkerCountForCpu(4, 2).resolved_count);
}

test "server thread count includes main raknet and workers" {
    try std.testing.expectEqual(@as(usize, 13), totalServerThreadCount(10));
    try std.testing.expectEqual(@as(usize, 4), totalServerThreadCount(1));
}

test "task queue completeness with swapRemove" {
    const allocator = std.testing.allocator;
    var completed_count: usize = 0;

    const Context = struct {
        counter: *usize,
    };

    const work_fn = struct {
        fn f(ctx: *anyopaque) void {
            const c: *Context = @ptrCast(@alignCast(ctx));
            _ = @atomicRmw(usize, c.counter, .Add, 1, .seq_cst);
        }
    }.f;

    const N: usize = 100;
    var contexts: [N]Context = undefined;
    for (&contexts) |*ctx| {
        ctx.* = .{ .counter = &completed_count };
    }

    var queue = ThreadedTaskQueue.init(allocator, 0);
    defer queue.deinit();
    try queue.start();

    for (&contexts) |*ctx| {
        try queue.enqueue(.{
            .work = work_fn,
            .ctx = @ptrCast(ctx),
        });
    }

    var attempts: usize = 0;
    while (attempts < 1000) : (attempts += 1) {
        queue.drainCompleted(std.math.maxInt(u64));
        if (@atomicLoad(usize, &completed_count, .seq_cst) == N) break;
        std.Thread.sleep(1_000_000);
    }

    try std.testing.expectEqual(N, @atomicLoad(usize, &completed_count, .seq_cst));
}
