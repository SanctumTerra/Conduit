const std = @import("std");
const Server = @import("./conduit/Server.zig").Server;
const Logger = @import("ZigNet").Logger;

pub fn main() !void {
    var server = try Server.init(.{
        // .allocator = CAllocator.get(),
    });
    defer {
        server.deinit();
        const leaked = CAllocator.getMemoryLeaks(); // Check leaks after cleanup
        Logger.ERROR("Leaked memory? {any}", .{leaked});
        CAllocator.deinit();
    }
    try server.listen();

    std.debug.print("Server started! Press 'Q' and Enter to quit...\n", .{});

    // Read input until user presses 'Q'
    const stdin = std.io.getStdIn().reader();
    var buffer: [256]u8 = undefined;

    while (true) {
        if (stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
            if (input) |line| {
                // Trim whitespace and convert to lowercase
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (std.mem.eql(u8, trimmed, "q") or std.mem.eql(u8, trimmed, "Q")) {
                    std.debug.print("Shutting down gracefully...\n", .{});
                    break;
                }
                // You can add other commands here if needed
                std.debug.print("Press 'Q' and Enter to quit...\n", .{});
            }
        } else |err| {
            Logger.ERROR("Error reading input: {any}", .{err});
            break;
        }
    }
}

const CAllocator = @import("CAllocator");
