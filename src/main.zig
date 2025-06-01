const std = @import("std");
const Callocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const BinaryStream = @import("BinaryStream");
const Socket = @import("./raknet/socket/socket.zig").Socket;
const Server = @import("./raknet/Server.zig").Server;

pub fn main() !void {
    defer _ = Callocator.deinit();

    var server = try Server.init(.{
        .port = 19132,
    });
    defer server.deinit();

    server.listen();

    while (true) {
        Callocator.getMemoryUsage();
        std.time.sleep(std.time.ns_per_s * 1);
    }
}
