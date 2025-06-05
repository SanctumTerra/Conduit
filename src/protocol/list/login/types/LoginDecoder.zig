const std = @import("std");
const json = std.json;
const base64 = std.base64;
const Allocator = std.mem.Allocator;

pub const TokenError = error{
    InvalidType,
    Malformed,
    InvalidPayload,
    Base64DecodeError,
    JsonParseError,
    OutOfMemory,
    InvalidData,
};

pub const DecodedToken = struct {
    header: json.Parsed(json.Value),
    payload: json.Parsed(json.Value),
    signature: []const u8,
    input: []const u8,

    pub fn deinit(self: *DecodedToken) void {
        self.header.deinit();
        self.payload.deinit();
    }
};

pub const PayloadOnly = struct {
    payload: json.Parsed(json.Value),

    pub fn deinit(self: *PayloadOnly) void {
        self.payload.deinit();
    }
};

pub const LoginDecoder = struct {
    allocator: Allocator,
    complete: bool,
    check_typ: ?[]const u8,

    pub fn init(allocator: Allocator) LoginDecoder {
        return .{
            .allocator = allocator,
            .complete = false,
            .check_typ = null,
        };
    }

    pub fn initWithOptions(allocator: Allocator, complete: bool, check_typ: ?[]const u8) LoginDecoder {
        return .{
            .allocator = allocator,
            .complete = complete,
            .check_typ = check_typ,
        };
    }

    pub fn decode(self: *LoginDecoder, token: []const u8) !union(enum) {
        payload_only: PayloadOnly,
        complete_token: DecodedToken,
    } {
        const separators = try self.validateTokenFormat(token);

        const header_b64 = token[0..separators.first];
        const payload_b64 = token[separators.first + 1 .. separators.last];
        const signature = token[separators.last + 1 ..];

        const header_parsed = self.decodeAndParseJson(header_b64) catch |err| {
            return err;
        };
        errdefer header_parsed.deinit();

        try self.validateHeaderType(header_parsed.value);

        const payload_parsed = self.decodeAndParseJson(payload_b64) catch |err| {
            return err;
        };
        errdefer payload_parsed.deinit();

        if (payload_parsed.value != .object) {
            return TokenError.InvalidPayload;
        }

        if (self.complete) {
            return .{ .complete_token = DecodedToken{
                .header = header_parsed,
                .payload = payload_parsed,
                .signature = signature,
                .input = token[0..separators.last],
            } };
        } else {
            header_parsed.deinit();
            return .{ .payload_only = PayloadOnly{ .payload = payload_parsed } };
        }
    }

    fn validateTokenFormat(self: *LoginDecoder, token: []const u8) !struct {
        first: usize,
        last: usize,
    } {
        _ = self;

        if (token.len == 0) return TokenError.Malformed;

        if (token.len >= 20) {
            var null_count: usize = 0;
            for (token[0..20]) |byte| {
                if (byte == 0) null_count += 1;
            }
            if (null_count > 10) return TokenError.InvalidData;
        }

        const first_separator = std.mem.indexOf(u8, token, ".") orelse
            return TokenError.Malformed;
        const last_separator = std.mem.lastIndexOf(u8, token, ".") orelse
            return TokenError.Malformed;

        if (first_separator >= last_separator) return TokenError.Malformed;

        return .{ .first = first_separator, .last = last_separator };
    }

    fn validateHeaderType(self: *LoginDecoder, header: json.Value) !void {
        if (self.check_typ) |expected_typ| {
            if (header == .object) {
                if (header.object.get("typ")) |typ_value| {
                    if (typ_value == .string) {
                        if (!std.mem.eql(u8, typ_value.string, expected_typ)) {
                            return TokenError.InvalidType;
                        }
                    }
                }
            }
        }
    }

    fn decodeAndParseJson(self: *LoginDecoder, base64_data: []const u8) !json.Parsed(json.Value) {
        const decoder = base64.url_safe_no_pad.Decoder;
        const decoded_size = decoder.calcSizeForSlice(base64_data) catch
            return TokenError.Base64DecodeError;

        const decoded_buf = try self.allocator.alloc(u8, decoded_size);
        defer self.allocator.free(decoded_buf);

        decoder.decode(decoded_buf, base64_data) catch
            return TokenError.Base64DecodeError;

        return json.parseFromSlice(json.Value, self.allocator, decoded_buf, .{}) catch
            TokenError.JsonParseError;
    }
};

pub fn createDecoder(allocator: Allocator, options: struct {
    complete: bool = false,
    check_typ: ?[]const u8 = null,
}) LoginDecoder {
    return LoginDecoder.initWithOptions(allocator, options.complete, options.check_typ);
}
