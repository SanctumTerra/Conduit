const std = @import("std");
const base64 = std.base64;
const json = std.json;

pub const JWTError = error{
    InvalidFormat,
    InvalidBase64,
    InvalidJSON,
    MissingParts,
};

pub const JWT = struct {
    header_parsed: json.Parsed(json.Value),
    payload_parsed: json.Parsed(json.Value),
    signature: []const u8,
    raw_header: []const u8,
    raw_payload: []const u8,

    allocator: std.mem.Allocator,

    pub fn decode(allocator: std.mem.Allocator, token: []const u8) !JWT {
        var parts = std.mem.splitScalar(u8, token, '.');

        const header_b64 = parts.next() orelse return JWTError.MissingParts;
        const payload_b64 = parts.next() orelse return JWTError.MissingParts;
        const signature_b64 = parts.next() orelse return JWTError.MissingParts;

        const header_decoded = try decodeBase64Url(allocator, header_b64);
        errdefer allocator.free(header_decoded);

        const header_parsed = json.parseFromSlice(
            json.Value,
            allocator,
            header_decoded,
            .{},
        ) catch return JWTError.InvalidJSON;
        errdefer header_parsed.deinit();

        const payload_decoded = try decodeBase64Url(allocator, payload_b64);
        errdefer allocator.free(payload_decoded);

        const payload_parsed = json.parseFromSlice(
            json.Value,
            allocator,
            payload_decoded,
            .{},
        ) catch return JWTError.InvalidJSON;
        errdefer payload_parsed.deinit();

        const signature_decoded = try decodeBase64Url(allocator, signature_b64);
        errdefer allocator.free(signature_decoded);

        return JWT{
            .header_parsed = header_parsed,
            .payload_parsed = payload_parsed,
            .signature = signature_decoded,
            .raw_header = header_decoded,
            .raw_payload = payload_decoded,
            .allocator = allocator,
        };
    }

    pub fn header(self: *const JWT) json.Value {
        return self.header_parsed.value;
    }

    pub fn payload(self: *const JWT) json.Value {
        return self.payload_parsed.value;
    }

    pub fn deinit(self: *JWT) void {
        self.header_parsed.deinit();
        self.payload_parsed.deinit();
        self.allocator.free(self.raw_header);
        self.allocator.free(self.raw_payload);
        self.allocator.free(self.signature);
    }

    pub fn verifyES384(self: *const JWT, public_key_x: []const u8, public_key_y: []const u8, token: []const u8) !bool {
        const P384 = std.crypto.ecc.P384;

        const dot_pos = std.mem.lastIndexOf(u8, token, ".") orelse return JWTError.InvalidFormat;
        const signed_data = token[0..dot_pos];

        var hash: [48]u8 = undefined;
        std.crypto.hash.sha2.Sha384.hash(signed_data, &hash, .{});

        if (self.signature.len != 96) return error.InvalidSignatureLength;

        const r = self.signature[0..48];
        const s = self.signature[48..96];

        if (public_key_x.len != 48 or public_key_y.len != 48) {
            return error.InvalidPublicKeyLength;
        }

        var pub_key_bytes: [97]u8 = undefined;
        pub_key_bytes[0] = 0x04;
        @memcpy(pub_key_bytes[1..49], public_key_x);
        @memcpy(pub_key_bytes[49..97], public_key_y);

        const public_key = P384.fromSec1(&pub_key_bytes) catch return error.InvalidPublicKey;

        var sig_bytes: [96]u8 = undefined;
        @memcpy(sig_bytes[0..48], r);
        @memcpy(sig_bytes[48..96], s);

        const signature = P384.Ecdsa.Signature.fromBytes(sig_bytes);
        const scalar = P384.scalar.Scalar.fromBytes(hash, .big);

        signature.verify(scalar, public_key) catch return false;
        return true;
    }
};

fn decodeBase64Url(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoder = base64.url_safe_no_pad;

    const decoded_len = decoder.Decoder.calcSizeForSlice(encoded) catch return error.InvalidBase64;
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);

    decoder.Decoder.decode(decoded, encoded) catch return error.InvalidBase64;
    return decoded;
}
