const std = @import("std");
const Callocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const BinaryStream = @import("BinaryStream");
const Socket = @import("./raknet/socket/socket.zig").Socket;
const Server = @import("./conduit/Server.zig").Server;

pub fn main() !void {
    defer _ = Callocator.deinit();

    var server = try Server.init(Callocator.get(), .{
        .address = "0.0.0.0",
        .port = 19132,
        .max_players = 60,
        .tick_rate = 20,
    });
    defer server.deinit();

    try server.start();

    while (true) {
        Callocator.getMemoryUsage();
        std.time.sleep(std.time.ns_per_s * 10);
    }
}
