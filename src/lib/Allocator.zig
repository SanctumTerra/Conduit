const std = @import("std");
const heap = std.heap;

var allocator = heap.GeneralPurposeAllocator(.{
    .safety = true,
    .enable_memory_limit = true,
    .retain_metadata = true,
    // .verbose_log = true,
}){};

pub fn get() std.mem.Allocator {
    return allocator.allocator();
}

/// Returns the memory usage in MB
pub fn getMemoryUsage() void {
    const bytes = allocator.total_requested_bytes;
    const mb = bytes / (1024 * 1024);
    std.debug.print("Memory usage: {} MB\n", .{mb});
    // const leaks = allocator.detectLeaks();
    // if (leaks) {
    // std.process.exit(1);
    // }
    // allocator.flushRetainedMetadata();
}

pub fn deinit() std.heap.Check {
    return allocator.deinit();
}
