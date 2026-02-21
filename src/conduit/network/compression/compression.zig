const std = @import("std");
pub const CompressionMethod = @import("./types.zig").CompressionMethod;

const c = @cImport({
    @cInclude("zlib.h");
});

pub const DecompressResult = struct {
    packets: [][]const u8,
    buffer: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: DecompressResult) void {
        self.allocator.free(self.buffer);
        self.allocator.free(self.packets);
    }
};

pub const Compression = struct {
    pub fn compress(
        packets: []const []const u8,
        method: CompressionMethod,
        threshold: u16,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        var framed_size: usize = 0;
        for (packets) |packet| {
            framed_size += varintSize(packet.len) + packet.len;
        }

        const should_compress = framed_size >= threshold and method == .Zlib;

        if (should_compress) {
            const max_compressed = c.compressBound(@intCast(framed_size));
            const buffer = try allocator.alloc(u8, @intCast(2 + max_compressed));
            errdefer allocator.free(buffer);

            buffer[0] = 254;
            buffer[1] = @intFromEnum(method);

            const framed_buffer = try allocator.alloc(u8, framed_size);
            defer allocator.free(framed_buffer);

            var write_pos: usize = 0;
            for (packets) |packet| {
                write_pos += writeVarInt(framed_buffer[write_pos..], packet.len);
                @memcpy(framed_buffer[write_pos..][0..packet.len], packet);
                write_pos += packet.len;
            }

            var stream: c.z_stream = undefined;
            stream.zalloc = null;
            stream.zfree = null;
            stream.@"opaque" = null;

            if (c.deflateInit2(&stream, c.Z_DEFAULT_COMPRESSION, c.Z_DEFLATED, -15, 8, c.Z_DEFAULT_STRATEGY) != c.Z_OK) {
                return error.ZlibInitFailed;
            }
            defer _ = c.deflateEnd(&stream);

            stream.next_in = @constCast(framed_buffer.ptr);
            stream.avail_in = @as(c_uint, @intCast(framed_size));
            stream.next_out = buffer.ptr + 2;
            stream.avail_out = @as(c_uint, @intCast(max_compressed));

            const ret = c.deflate(&stream, c.Z_FINISH);
            if (ret != c.Z_STREAM_END) {
                return error.ZlibDeflateFailed;
            }

            const actual_size = 2 + (max_compressed - stream.avail_out);
            return allocator.realloc(buffer, actual_size);
        } else {
            const header_size: usize = if (method == .NotPresent) 1 else 2;
            const buffer = try allocator.alloc(u8, header_size + framed_size);
            errdefer allocator.free(buffer);

            buffer[0] = 254;
            if (method != .NotPresent) {
                buffer[1] = 0xFF;
            }

            var write_pos = header_size;
            for (packets) |packet| {
                write_pos += writeVarInt(buffer[write_pos..], packet.len);
                @memcpy(buffer[write_pos..][0..packet.len], packet);
                write_pos += packet.len;
            }

            return buffer;
        }
    }

    pub fn decompress(
        data: []const u8,
        allocator: std.mem.Allocator,
    ) !DecompressResult {
        if (data.len == 0 or data[0] != 254) {
            const owned = try allocator.dupe(u8, data);
            errdefer allocator.free(owned);
            const packets = try allocator.alloc([]const u8, 1);
            packets[0] = owned;
            return .{ .packets = packets, .buffer = owned, .allocator = allocator };
        }

        const method: CompressionMethod = if (data.len > 1) switch (data[1]) {
            @as(u8, @intFromEnum(CompressionMethod.Zlib)) => .Zlib,
            @as(u8, @intFromEnum(CompressionMethod.NotPresent)) => .NotPresent,
            @as(u8, @intFromEnum(CompressionMethod.Snappy)) => .Snappy,
            @as(u8, @intFromEnum(CompressionMethod.None)) => .None,
            else => .NotPresent,
        } else .NotPresent;

        var payload = data;
        if (method != .NotPresent and data.len > 1) {
            payload = payload[2..];
        } else {
            payload = payload[1..];
        }

        if (method == .Zlib) {
            const decompressed = try zlibInflate(payload, allocator);
            errdefer allocator.free(decompressed);
            const packets = try unframe(decompressed, allocator);
            return .{ .packets = packets, .buffer = decompressed, .allocator = allocator };
        }

        if (method == .Snappy) {
            const empty = try allocator.alloc(u8, 0);
            const packets = try allocator.alloc([]const u8, 0);
            return .{ .packets = packets, .buffer = empty, .allocator = allocator };
        }

        const owned = try allocator.dupe(u8, payload);
        errdefer allocator.free(owned);
        const packets = try unframe(owned, allocator);
        return .{ .packets = packets, .buffer = owned, .allocator = allocator };
    }

    fn zlibInflate(input: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var stream: c.z_stream = undefined;
        stream.zalloc = null;
        stream.zfree = null;
        stream.@"opaque" = null;
        stream.next_in = @constCast(input.ptr);
        stream.avail_in = @as(c_uint, @intCast(input.len));

        if (c.inflateInit2(&stream, -15) != c.Z_OK) {
            return error.ZlibInitFailed;
        }
        defer _ = c.inflateEnd(&stream);

        var out = try std.ArrayList(u8).initCapacity(allocator, input.len * 4);
        defer out.deinit(allocator);

        const chunk_size = 1024 * 256;
        var chunk: [chunk_size]u8 = undefined;

        while (true) {
            stream.next_out = &chunk;
            stream.avail_out = chunk_size;

            const ret = c.inflate(&stream, c.Z_NO_FLUSH);
            const have = chunk_size - stream.avail_out;
            try out.appendSlice(allocator, chunk[0..have]);

            if (ret == c.Z_STREAM_END) break;
            if (ret != c.Z_OK) return error.ZlibInflateFailed;
        }

        return out.toOwnedSlice(allocator);
    }

    fn unframe(payload: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
        var count: usize = 0;
        var offset: usize = 0;
        while (offset < payload.len) {
            const v = readVarInt(payload[offset..]);
            offset += v.size + v.value;
            count += 1;
        }

        const packets = try allocator.alloc([]const u8, count);
        offset = 0;
        var idx: usize = 0;
        while (offset < payload.len) : (idx += 1) {
            const v = readVarInt(payload[offset..]);
            offset += v.size;
            packets[idx] = payload[offset..][0..v.value];
            offset += v.value;
        }

        return packets;
    }

    inline fn varintSize(value: usize) usize {
        if (value < 0x80) return 1;
        if (value < 0x4000) return 2;
        if (value < 0x200000) return 3;
        if (value < 0x10000000) return 4;
        return 5;
    }

    inline fn writeVarInt(buffer: []u8, value: usize) usize {
        var val = value;
        var pos: usize = 0;
        while (val >= 0x80) {
            buffer[pos] = @intCast((val & 0x7F) | 0x80);
            val >>= 7;
            pos += 1;
        }
        buffer[pos] = @intCast(val & 0x7F);
        return pos + 1;
    }

    inline fn readVarInt(buffer: []const u8) struct { value: u32, size: usize } {
        var result: u32 = 0;
        var shift: u5 = 0;
        var pos: usize = 0;
        while (pos < buffer.len) : (pos += 1) {
            const byte = buffer[pos];
            result |= @as(u32, byte & 0x7F) << shift;
            if ((byte & 0x80) == 0) break;
            shift += 7;
        }
        return .{ .value = result, .size = pos + 1 };
    }
};
