pub const IdentityData = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    xuid: ?[]const u8,
    identity: ?[]const u8,
    display: ?[]const u8,
    titleId: ?[]const u8,
    sandboxId: ?[]const u8,
    extraData: ?std.json.Value = null,

    pub fn parseFromTokens(client_token: []const u8, identity_token: []const u8) !Self {
        const allocator = CAllocator.get();

        const tokens = LoginDecoder.LoginTokens{
            .client = client_token,
            .identity = identity_token,
        };

        var decoded = LoginDecoder.LoginDecoder.decode(tokens) catch |err| {
            Logger.ERROR("Failed to decode login tokens: {any}", .{err});
            return err;
        };
        defer decoded.deinit(allocator);

        var self = Self{
            .allocator = allocator,
            .xuid = null,
            .identity = null,
            .display = null,
            .titleId = null,
            .sandboxId = null,
            .extraData = null,
        };

        // Extract specific fields from identity data if available
        if (decoded.identity_data) |identity| {
            if (identity.XUID) |xuid_val| {
                self.xuid = try allocator.dupe(u8, xuid_val);
            }

            if (identity.identity) |identity_val| {
                self.identity = try allocator.dupe(u8, identity_val);
            }

            if (identity.displayName) |display_val| {
                self.display = try allocator.dupe(u8, display_val);
            }

            if (identity.titleId) |title_val| {
                self.titleId = try allocator.dupe(u8, title_val);
            }

            if (identity.sandBoxId) |sandbox_val| {
                self.sandboxId = try allocator.dupe(u8, sandbox_val);
            }
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.xuid) |xuid| self.allocator.free(xuid);
        if (self.identity) |identity| self.allocator.free(identity);
        if (self.display) |display| self.allocator.free(display);
        if (self.titleId) |title| self.allocator.free(title);
        if (self.sandboxId) |sandbox| self.allocator.free(sandbox);
    }
};

const IdentityError = error{
    MissingChain,
    InvalidData,
};

const std = @import("std");
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const LoginDecoder = @import("../LoginDecoder.zig");
