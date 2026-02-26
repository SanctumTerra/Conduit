const std = @import("std");

pub const TaskFn = *const fn (ctx: *anyopaque) bool;

pub const Task = struct {
    func: TaskFn,
    ctx: *anyopaque,
    name: []const u8,
    owner_id: i64 = 0,
    cleanup: ?*const fn (*anyopaque) void = null,
};

pub const TaskQueue = struct {
    tasks: std.ArrayList(Task),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TaskQueue {
        return .{
            .tasks = std.ArrayList(Task){ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TaskQueue) void {
        for (self.tasks.items) |task| {
            if (task.cleanup) |cb| cb(task.ctx);
        }
        self.tasks.deinit(self.allocator);
    }

    pub fn enqueue(self: *TaskQueue, task: Task) !void {
        try self.tasks.append(self.allocator, task);
    }

    pub fn cancelByOwner(self: *TaskQueue, name: []const u8, owner_id: i64, cleanup: ?*const fn (*anyopaque) void) void {
        var i: usize = 0;
        while (i < self.tasks.items.len) {
            const task = self.tasks.items[i];
            if (task.owner_id == owner_id and std.mem.eql(u8, task.name, name)) {
                if (cleanup) |cb| cb(task.ctx);
                _ = self.tasks.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Runs tasks until budget_ns is exhausted. Returns true if work was done.
    pub fn runUntil(self: *TaskQueue, tick_start: i128, budget_ns: u64) bool {
        var did_work = false;
        while (self.tasks.items.len > 0) {
            const elapsed: u64 = @intCast(@max(0, std.time.nanoTimestamp() - tick_start));
            if (elapsed >= budget_ns) break;

            const done = self.tasks.items[0].func(self.tasks.items[0].ctx);
            did_work = true;
            if (done) {
                _ = self.tasks.orderedRemove(0);
            }
        }
        return did_work;
    }

    pub fn pending(self: *const TaskQueue) usize {
        return self.tasks.items.len;
    }
};
