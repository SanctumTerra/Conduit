const std = @import("std");
const Conduit = @import("conduit").Conduit;

pub fn main() !void {
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

    std.Thread.sleep(std.time.ns_per_min * 5);
    try conduit.stop();
}
