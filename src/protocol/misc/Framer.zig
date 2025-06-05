const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;

pub const Framer = struct {
    pub fn frame(buffers: []const []const u8) []const u8 {
        const allocator = CAllocator.get();
        var stream = BinaryStream.init(allocator, &[_]u8{}, 0);
        defer stream.deinit();

        for (buffers) |buffer| {
            stream.writeVarInt(@intCast(buffer.len), .Big);
            stream.write(buffer);
        }

        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for pong packet");
    }

    pub fn unframe(data: []const u8) ![][]const u8 {
        const allocator = CAllocator.get();
        var stream = BinaryStream.init(allocator, data, 0);
        defer stream.deinit();

        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();

        if (data.len > 0 and data[0] == 6 and data.len == 7) {
            const buffer_view = data[1..];
            const buffer_owned_copy = allocator.dupe(u8, buffer_view) catch |err| {
                std.debug.print("Framer.unframe: Failed to duplicate buffer_view in special case ({d} bytes): {any}\n", .{ buffer_view.len, err });
                return err;
            };
            try list.append(buffer_owned_copy);
            return list.toOwnedSlice();
        }

        while (stream.position < data.len) {
            if (stream.position + 1 > data.len) {
                std.debug.print("Breaking early: not enough bytes for length\n", .{});
                break;
            }

            const length = stream.readVarInt(.Big);

            if (length > 131072) {
                std.debug.print("Unreasonable frame length: {d}, likely parsing error\n", .{length});
                break;
            }

            if (stream.position + length > data.len) {
                std.debug.print("Not enough bytes for frame: need {d}, have {d}\n", .{ length, data.len - stream.position });
                break;
            }

            const frame_view = stream.read(length);
            const frame_owned_copy = allocator.dupe(u8, frame_view) catch |err| {
                std.debug.print("Failed to duplicate frame_view: {any}\n", .{err});
                return err;
            };
            try list.append(frame_owned_copy);
        }

        return list.toOwnedSlice();
    }

    /// Free memory allocated by unframe
    pub fn freeUnframedData(frames: [][]const u8) void {
        const allocator = CAllocator.get();
        for (frames) |frame_slice| {
            allocator.free(frame_slice);
        }
        allocator.free(frames);
    }
};
