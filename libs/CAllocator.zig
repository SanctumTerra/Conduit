const std = @import("std");

var gpa_state = std.heap.DebugAllocator(.{}){};
var gpa = gpa_state.allocator();

pub inline fn get() std.mem.Allocator {
    return gpa;
}

pub fn deinit() void {
    _ = gpa_state.deinit();
}

pub fn getMemoryLeaks() bool {
    return gpa_state.detectLeaks();
}
