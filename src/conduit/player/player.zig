const std = @import("std");
const Raknet = @import("Raknet");
const LoginData = @import("protocol").Login.Decoder.LoginData;
pub const NetworkHandler = @import("../network/network-handler.zig").NetworkHandler;

pub const Player = struct {
    allocator: std.mem.Allocator,
    connection: *Raknet.Connection,
    network: *NetworkHandler,
    loginData: LoginData,
    runtimeId: i64,

    xuid: []const u8,
    username: []const u8,
    uuid: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: *Raknet.Connection,
        network: *NetworkHandler,
        loginData: LoginData,
        runtimeId: i64,
    ) !Player {
        return Player{
            .allocator = allocator,
            .connection = connection,
            .network = network,
            .loginData = loginData,
            .runtimeId = runtimeId,
            .xuid = loginData.identity_data.xuid,
            .username = loginData.identity_data.display_name,
            .uuid = loginData.identity_data.identity,
        };
    }

    pub fn deinit(self: *Player) void {
        self.loginData.deinit();
    }

    pub fn disconnect(self: *Player) !void {
        if (self.network.conduit.players.fetchRemove(self.runtimeId)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }
};
