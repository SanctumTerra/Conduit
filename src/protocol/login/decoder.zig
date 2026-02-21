const std = @import("std");
const jwt = @import("./jwt.zig");
const types = @import("./types.zig");

pub const LoginData = struct {
    identity_public_key: []const u8,
    identity_data: types.IdentityData,
    client_data: types.ClientData,

    client_jwt: jwt.JWT,
    identity_jwt: jwt.JWT,
    chain_parsed: std.json.Parsed(std.json.Value),
    cert_parsed: std.json.Parsed(std.json.Value),

    allocator: std.mem.Allocator,

    pub fn deinit(self: *LoginData) void {
        self.allocator.free(self.identity_public_key);
        self.identity_data.deinit(self.allocator);
        self.client_data.deinit(self.allocator);
        self.client_jwt.deinit();
        self.identity_jwt.deinit();
        self.cert_parsed.deinit();
        self.chain_parsed.deinit();
    }

    pub fn getClientData(self: *const LoginData) std.json.Value {
        return self.client_jwt.payload();
    }

    pub fn getIdentityClaims(self: *const LoginData) std.json.Value {
        return self.identity_jwt.payload();
    }
};

pub fn decodeLoginChain(allocator: std.mem.Allocator, chain_json: []const u8, client_data_token: []const u8) !LoginData {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        chain_json,
        .{},
    ) catch |err| {
        std.debug.print("Failed to parse chain JSON: {}\n", .{err});
        return err;
    };
    errdefer parsed.deinit();

    const certificate_str = parsed.value.object.get("Certificate") orelse {
        std.debug.print("Missing 'Certificate' field in JSON\n", .{});
        return error.MissingCertificate;
    };

    const cert_parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        certificate_str.string,
        .{},
    ) catch |err| {
        std.debug.print("Failed to parse Certificate JSON: {}\n", .{err});
        return err;
    };
    errdefer cert_parsed.deinit();

    const chain_array = cert_parsed.value.object.get("chain") orelse {
        std.debug.print("Missing 'chain' field in Certificate\n", .{});
        return error.MissingChain;
    };
    const chain = chain_array.array;

    if (chain.items.len == 0) return error.EmptyChain;

    const last_token = chain.items[chain.items.len - 1].string;
    var identity_jwt = try jwt.JWT.decode(allocator, last_token);
    errdefer identity_jwt.deinit();

    const identity_pub_key_field = identity_jwt.payload().object.get("identityPublicKey") orelse
        return error.MissingIdentityPublicKey;

    const identity_public_key = try allocator.dupe(u8, identity_pub_key_field.string);
    errdefer allocator.free(identity_public_key);

    var identity_data = try types.IdentityData.parse(allocator, identity_jwt.payload());
    errdefer identity_data.deinit(allocator);

    var client_jwt = try jwt.JWT.decode(allocator, client_data_token);
    errdefer client_jwt.deinit();

    var client_data = try types.ClientData.parse(allocator, client_jwt.payload());
    errdefer client_data.deinit(allocator);

    return LoginData{
        .identity_public_key = identity_public_key,
        .identity_data = identity_data,
        .client_data = client_data,
        .client_jwt = client_jwt,
        .identity_jwt = identity_jwt,
        .chain_parsed = parsed,
        .cert_parsed = cert_parsed,
        .allocator = allocator,
    };
}

pub fn parsePublicKey(allocator: std.mem.Allocator, key_b64: []const u8) !struct { x: [48]u8, y: [48]u8 } {
    _ = allocator;

    const decoder = std.base64.standard;
    var key_bytes: [200]u8 = undefined;
    const decoded_len = try decoder.Decoder.decode(&key_bytes, key_b64);

    if (decoded_len == 97 and key_bytes[0] == 0x04) {
        var result: struct { x: [48]u8, y: [48]u8 } = undefined;
        @memcpy(&result.x, key_bytes[1..49]);
        @memcpy(&result.y, key_bytes[49..97]);
        return result;
    }

    return error.UnsupportedKeyFormat;
}
