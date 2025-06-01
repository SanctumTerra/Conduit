const std = @import("std");

pub const Connection = struct {
    address: std.net.Address,

    pub fn init(address: std.net.Address) Connection {
        return .{ .address = address };
    }

    pub fn deinit(self: *Connection) void {
        _ = self;
    }
};
