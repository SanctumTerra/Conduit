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

const WORKER_COUNT = 4;

pub const ThreadedTaskQueue = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(ThreadedTask),
    completed: std.ArrayList(ThreadedTask),
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    workers: [WORKER_COUNT]?std.Thread,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) ThreadedTaskQueue {
        return .{
            .allocator = allocator,
            .pending = std.ArrayList(ThreadedTask){ .items = &.{}, .capacity = 0 },
            .completed = std.ArrayList(ThreadedTask){ .items = &.{}, .capacity = 0 },
            .mutex = .{},
            .cond = .{},
            .workers = .{null} ** WORKER_COUNT,
            .running = false,
        };
    }

    pub fn start(self: *ThreadedTaskQueue) !void {
        self.running = true;
        for (&self.workers) |*w| {
            w.* = try std.Thread.spawn(.{}, workerLoop, .{self});
        }
    }

    pub fn enqueue(self: *ThreadedTaskQueue, task: ThreadedTask) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.pending.append(self.allocator, task);
        self.cond.signal();
    }

    pub fn drainCompleted(self: *ThreadedTaskQueue) void {
        self.mutex.lock();
        if (self.completed.items.len == 0) {
            self.mutex.unlock();
            return;
        }
        var local = self.completed;
        self.completed = std.ArrayList(ThreadedTask){ .items = &.{}, .capacity = 0 };
        self.mutex.unlock();

        for (local.items) |task| {
            if (task.callback) |cb| cb(task.ctx);
        }
        local.deinit(self.allocator);
    }

    pub fn stop(self: *ThreadedTaskQueue) void {
        self.mutex.lock();
        self.running = false;
        self.cond.broadcast();
        self.mutex.unlock();

        for (&self.workers) |*w| {
            if (w.*) |t| {
                t.join();
                w.* = null;
            }
        }
    }

    pub fn deinit(self: *ThreadedTaskQueue) void {
        self.stop();
        for (self.pending.items) |task| {
            if (task.cleanup) |c| c(task.ctx);
        }
        if (self.pending.capacity > 0) self.pending.deinit(self.allocator);
        for (self.completed.items) |task| {
            if (task.cleanup) |c| c(task.ctx);
        }
        if (self.completed.capacity > 0) self.completed.deinit(self.allocator);
    }

    fn workerLoop(self: *ThreadedTaskQueue) void {
        while (true) {
            self.mutex.lock();
            while (self.pending.items.len == 0 and self.running) {
                self.cond.wait(&self.mutex);
            }
            if (!self.running and self.pending.items.len == 0) {
                self.mutex.unlock();
                return;
            }
            const task = self.pending.orderedRemove(0);
            self.mutex.unlock();

            task.work(task.ctx);

            self.mutex.lock();
            self.completed.append(self.allocator, task) catch {
                if (task.cleanup) |c| c(task.ctx);
            };
            self.mutex.unlock();
        }
    }
};
