const std = @import("std");
const LoginDecoder = @import("../../../protocol/list/login/types/LoginDecoder.zig").LoginDecoder;
const Logger = @import("Logger").Logger;

pub const IdentityData = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,

    xuid: ?[]const u8 = null,
    identity: ?[]const u8 = null,
    displayName: ?[]const u8 = null,
    titleId: ?[]const u8 = null,
    sandboxId: ?[]const u8 = null,

    extraData: ?std.json.Value = null,

    chainLength: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.xuid) |xuid| self.allocator.free(xuid);
        if (self.identity) |identity| self.allocator.free(identity);
        if (self.displayName) |displayName| self.allocator.free(displayName);
        if (self.titleId) |titleId| self.allocator.free(titleId);
        if (self.sandboxId) |sandboxId| self.allocator.free(sandboxId);

        self.extraData = null;
    }

    pub fn parseFromRaw(self: *Self, raw_identity: []const u8) !void {
        self.deinit();

        self.xuid = null;
        self.identity = null;
        self.displayName = null;
        self.titleId = null;
        self.sandboxId = null;
        self.extraData = null;
        self.chainLength = 0;

        var identity_parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, raw_identity, .{});
        defer identity_parsed.deinit();

        if (identity_parsed.value != .object) {
            return error.InvalidIdentityFormat;
        }

        const chain_value = identity_parsed.value.object.get("chain") orelse {
            return error.MissingChain;
        };

        if (chain_value != .array) {
            return error.InvalidChainFormat;
        }

        self.chainLength = chain_value.array.items.len;

        var decoder = LoginDecoder.init(self.allocator);

        for (chain_value.array.items) |token_str| {
            if (token_str != .string) continue;

            var token_decoded = decoder.decode(token_str.string) catch |err| {
                Logger.ERROR("Failed to decode chain token: {any}", .{err});
                continue;
            };
            defer switch (token_decoded) {
                .payload_only => |*p| p.deinit(),
                .complete_token => |*t| t.deinit(),
            };

            switch (token_decoded) {
                .payload_only => |payload_wrapper| {
                    if (payload_wrapper.payload.value != .object) continue;

                    self.extractField(payload_wrapper.payload.value, "xuid", &self.xuid);
                    self.extractField(payload_wrapper.payload.value, "identity", &self.identity);
                    self.extractField(payload_wrapper.payload.value, "displayName", &self.displayName);
                    self.extractField(payload_wrapper.payload.value, "titleId", &self.titleId);
                    self.extractField(payload_wrapper.payload.value, "sandboxId", &self.sandboxId);

                    if (payload_wrapper.payload.value.object.get("extraData")) |extra| {
                        if (extra == .object) {
                            if (self.xuid == null) self.extractField(extra, "XUID", &self.xuid);
                            if (self.identity == null) self.extractField(extra, "identity", &self.identity);
                            if (self.displayName == null) self.extractField(extra, "displayName", &self.displayName);
                            if (self.titleId == null) self.extractField(extra, "titleId", &self.titleId);
                            if (self.sandboxId == null) self.extractField(extra, "sandboxId", &self.sandboxId);
                        }
                    }
                },
                .complete_token => |token_wrapper| {
                    if (token_wrapper.payload.value != .object) continue;
                    self.extractField(token_wrapper.payload.value, "xuid", &self.xuid);
                    self.extractField(token_wrapper.payload.value, "identity", &self.identity);
                    self.extractField(token_wrapper.payload.value, "displayName", &self.displayName);
                    self.extractField(token_wrapper.payload.value, "titleId", &self.titleId);
                    self.extractField(token_wrapper.payload.value, "sandboxId", &self.sandboxId);
                    if (token_wrapper.payload.value.object.get("extraData")) |extra| {
                        if (extra == .object) {
                            if (self.xuid == null) self.extractField(extra, "XUID", &self.xuid);
                            if (self.identity == null) self.extractField(extra, "identity", &self.identity);
                            if (self.displayName == null) self.extractField(extra, "displayName", &self.displayName);
                            if (self.titleId == null) self.extractField(extra, "titleId", &self.titleId);
                            if (self.sandboxId == null) self.extractField(extra, "sandboxId", &self.sandboxId);
                        }
                    }
                },
            }
        }
    }

    fn extractField(self: *Self, payload_value: std.json.Value, field_name: []const u8, target: *?[]const u8) void {
        if (target.* != null) return;

        if (payload_value.object.get(field_name)) |value| {
            if (value == .string) {
                const str = value.string;
                if (str.len == 0) return;

                if (target.*) |existing| {
                    self.allocator.free(existing);
                    target.* = null;
                }

                const dup = self.allocator.alloc(u8, str.len) catch |err| {
                    Logger.ERROR("Failed to allocate memory for {s}: {any}", .{ field_name, err });
                    return;
                };
                @memcpy(dup, str);
                target.* = dup;
            }
        }
    }
};
