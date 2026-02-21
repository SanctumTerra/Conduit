const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const Uuid = struct {
    pub fn read(stream: *BinaryStream) ![]const u8 {
        const start_pos = stream.offset;
        _ = try stream.read(16);
        return stream.buffer.items[start_pos..stream.offset];
    }

    pub fn write(stream: *BinaryStream, value: []const u8) !void {
        if (value.len == 36) {
            var uuid_bytes: [32]u8 = undefined;
            var idx: usize = 0;

            for (value) |c| {
                if (c != '-') {
                    uuid_bytes[idx] = c;
                    idx += 1;
                }
            }

            var bytes: [16]u8 = undefined;
            for (0..16) |i| {
                bytes[i] = try std.fmt.parseInt(u8, uuid_bytes[i * 2 .. i * 2 + 2], 16);
            }

            var msb: [8]u8 = undefined;
            var lsb: [8]u8 = undefined;

            for (0..8) |i| {
                msb[i] = bytes[7 - i];
                lsb[i] = bytes[15 - i];
            }

            try stream.write(&msb);
            try stream.write(&lsb);
        } else if (value.len == 16) {
            try stream.write(value);
        } else {
            return error.InvalidUuidLength;
        }
    }
};
