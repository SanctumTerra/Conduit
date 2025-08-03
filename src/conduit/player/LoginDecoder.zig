const std = @import("std");
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const ClientData = @import("types/ClientData.zig").ClientData;

pub const IdentityDataExtracted = struct {
    XUID: ?[]const u8 = null,
    displayName: ?[]const u8 = null,
    identity: ?[]const u8 = null,
    sandBoxId: ?[]const u8 = null,
    titleId: ?[]const u8 = null,

    pub fn deinit(self: *IdentityDataExtracted, allocator: std.mem.Allocator) void {
        if (self.XUID) |val| allocator.free(val);
        if (self.displayName) |val| allocator.free(val);
        if (self.identity) |val| allocator.free(val);
        if (self.sandBoxId) |val| allocator.free(val);
        if (self.titleId) |val| allocator.free(val);
    }
};

pub const LoginTokenData = struct {
    client_data: ?ClientData = null,
    identity_data: ?IdentityDataExtracted = null,
    public_key: ?[]const u8 = null,

    pub fn deinit(self: *LoginTokenData, allocator: std.mem.Allocator) void {
        if (self.client_data) |*client| {
            client.deinit();
        }
        if (self.identity_data) |*identity| {
            identity.deinit(allocator);
        }
        if (self.public_key) |key| {
            allocator.free(key);
        }
    }
};

pub const LoginTokens = struct {
    client: []const u8,
    identity: []const u8,
};

pub const LoginDecoder = struct {
    const Self = @This();

    pub fn decode(tokens: LoginTokens) !LoginTokenData {
        const allocator = CAllocator.get();

        // Decode client data
        const client_jwt = try Self.decodeJWT(tokens.client);
        defer client_jwt.deinit();

        var client_data = ClientData.fromJson(allocator, client_jwt.value) catch |err| {
            Logger.ERROR("Failed to parse client data: {any}", .{err});
            return err;
        };
        errdefer client_data.deinit();

        // Parse identity data from tokens
        const identity_parsed = std.json.parseFromSlice(std.json.Value, allocator, tokens.identity, .{}) catch |err| {
            Logger.ERROR("Failed to parse identity JSON: {any}", .{err});
            return err;
        };
        defer identity_parsed.deinit();

        const certificate_obj = identity_parsed.value.object.get("Certificate") orelse {
            Logger.ERROR("Missing Certificate in identity data", .{});
            return error.MissingCertificate;
        };

        if (certificate_obj != .string) {
            Logger.ERROR("Certificate is not a string", .{});
            return error.InvalidCertificate;
        }

        // Parse the certificate chain
        const chains_parsed = std.json.parseFromSlice(std.json.Value, allocator, certificate_obj.string, .{}) catch |err| {
            Logger.ERROR("Failed to parse certificate chain: {any}", .{err});
            return err;
        };
        defer chains_parsed.deinit();

        const chain_array = chains_parsed.value.object.get("chain") orelse {
            Logger.ERROR("Missing chain in certificate", .{});
            return error.MissingChain;
        };

        if (chain_array != .array) {
            Logger.ERROR("Chain is not an array", .{});
            return error.InvalidChain;
        }

        // Decode each chain token
        var identity_data: ?IdentityDataExtracted = null;
        var public_key: ?[]const u8 = null;

        // Error cleanup in case of partial allocation
        errdefer {
            if (identity_data) |*data| {
                data.deinit(allocator);
            }
            if (public_key) |key| {
                allocator.free(key);
            }
        }

        for (chain_array.array.items) |chain_token| {
            if (chain_token != .string) continue;

            const decoded_chain = Self.decodeJWT(chain_token.string) catch |err| {
                Logger.WARN("Failed to decode chain token: {any}", .{err});
                continue;
            };
            defer decoded_chain.deinit();

            // Look for extraData (identity data) - only take the first one
            if (identity_data == null) {
                if (decoded_chain.value.object.get("extraData")) |extra_data| {
                    if (extra_data == .object) {
                        var extracted = IdentityDataExtracted{};

                        if (extra_data.object.get("XUID")) |xuid| {
                            if (xuid == .string) {
                                extracted.XUID = try allocator.dupe(u8, xuid.string);
                            }
                        }

                        if (extra_data.object.get("displayName")) |display| {
                            if (display == .string) {
                                extracted.displayName = try allocator.dupe(u8, display.string);
                            }
                        }

                        if (extra_data.object.get("identity")) |ident| {
                            if (ident == .string) {
                                extracted.identity = try allocator.dupe(u8, ident.string);
                            }
                        }

                        if (extra_data.object.get("sandBoxId")) |sandbox| {
                            if (sandbox == .string) {
                                extracted.sandBoxId = try allocator.dupe(u8, sandbox.string);
                            }
                        }

                        if (extra_data.object.get("titleId")) |title| {
                            if (title == .string) {
                                extracted.titleId = try allocator.dupe(u8, title.string);
                            }
                        }

                        identity_data = extracted;
                    }
                }
            }

            // Look for identityPublicKey (public key) - only take the first one
            if (public_key == null) {
                if (decoded_chain.value.object.get("identityPublicKey")) |pub_key| {
                    if (pub_key == .string) {
                        public_key = try allocator.dupe(u8, pub_key.string);
                    }
                }
            }
        }

        return LoginTokenData{
            .client_data = client_data,
            .identity_data = identity_data,
            .public_key = public_key,
        };
    }

    fn decodeJWT(token: []const u8) !std.json.Parsed(std.json.Value) {
        const allocator = CAllocator.get();

        // Find the payload part (between first and second dot)
        var dot_count: u8 = 0;
        var payload_start: usize = 0;
        var payload_end: usize = token.len;

        for (token, 0..) |char, i| {
            if (char == '.') {
                dot_count += 1;
                if (dot_count == 1) {
                    payload_start = i + 1;
                } else if (dot_count == 2) {
                    payload_end = i;
                    break;
                }
            }
        }

        if (dot_count < 2) {
            Logger.ERROR("Invalid JWT format: not enough dots", .{});
            return error.InvalidJWTFormat;
        }

        const payload_b64 = token[payload_start..payload_end];

        // Decode base64url
        const decoded_payload = try Self.decodeBase64Url(allocator, payload_b64);
        defer allocator.free(decoded_payload);

        // Parse JSON
        return std.json.parseFromSlice(std.json.Value, allocator, decoded_payload, .{});
    }

    fn decodeBase64Url(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        // Convert base64url to base64
        var base64_input = try allocator.alloc(u8, input.len + 4); // Extra space for padding
        defer allocator.free(base64_input);

        // Replace URL-safe characters
        for (input, 0..) |char, i| {
            base64_input[i] = switch (char) {
                '-' => '+',
                '_' => '/',
                else => char,
            };
        }

        // Add padding if needed
        const padding_needed = (4 - (input.len % 4)) % 4;
        var actual_len = input.len;
        for (0..padding_needed) |i| {
            base64_input[input.len + i] = '=';
            actual_len += 1;
        }

        // Decode base64
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(base64_input[0..actual_len]);
        const decoded = try allocator.alloc(u8, decoded_len);

        try decoder.decode(decoded, base64_input[0..actual_len]);
        return decoded;
    }
};
