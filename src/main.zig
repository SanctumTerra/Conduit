const std = @import("std");
const builtin = @import("builtin");
const Conduit = @import("conduit").Conduit;

const winmm = if (builtin.os.tag == .windows) struct {
    extern "winmm" fn timeBeginPeriod(uPeriod: c_uint) callconv(.winapi) c_uint;
    extern "winmm" fn timeEndPeriod(uPeriod: c_uint) callconv(.winapi) c_uint;
} else struct {};

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        _ = winmm.timeBeginPeriod(1);
    }
    const is_debug = @import("builtin").mode == .Debug;

    if (is_debug) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        defer {
            const leaked = gpa.deinit();
            if (leaked == .leak) {
                std.debug.print("Memory leak detected!\n", .{});
            } else {
                std.debug.print("No memory leak detected!\n", .{});
            }
        }

        var conduit = try Conduit.init(allocator);
        defer conduit.deinit();

        try conduit.start();

        while (conduit.raknet.running) {
            std.Thread.sleep(std.time.ns_per_s);
        }
    } else {
        const allocator = std.heap.c_allocator;

        var conduit = try Conduit.init(allocator);
        defer conduit.deinit();

        try conduit.start();

        while (conduit.raknet.running) {
            std.Thread.sleep(std.time.ns_per_s);
        }
    }
}
