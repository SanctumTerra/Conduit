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
            stream.writeVarInt(@intCast(buffer.len));
            stream.write(buffer);
        }

        return stream.getBufferOwned(CAllocator.get()) catch {
            Logger.ERROR("Failed to allocate memory for frame packet", .{});
            return &[_]u8{};
        };
    }

    pub fn unframe(data: []const u8) ![][]const u8 {
        const allocator = CAllocator.get();
        var stream = BinaryStream.init(allocator, data, 0);
        defer stream.deinit();

        var list = std.ArrayList([]const u8).init(allocator);
        errdefer {
            // Clean up on error
            for (list.items) |frame_slice| {
                allocator.free(frame_slice);
            }
            list.deinit();
        }

        // // Special case handling
        // if (data.len == 7 and data[0] == 6) {
        //     const buffer_view = data[1..];
        //     const buffer_owned_copy = try allocator.dupe(u8, buffer_view);
        //     try list.append(buffer_owned_copy);
        //     return try list.toOwnedSlice();
        // }

        while (stream.offset < data.len) {
            if (stream.offset + 1 > data.len) break;

            const length = stream.readVarInt();

            // This is pretty much 2.5x the size of Login packet and no other packet is as big.
            if (length > 131072 * 5) {
                Logger.WARN("Unreasonable frame length: {d}, likely parsing error", .{length});
                break;
            }

            if (stream.offset + length > data.len) {
                Logger.WARN("Not enough bytes for frame: need {d}, have {d}", .{ length, data.len - stream.offset });
                break;
            }

            const frame_view = stream.read(length);
            const frame_owned_copy = try allocator.dupe(u8, frame_view);
            // defer allocator.free(frame_owned_copy); // can not do it here cause then it invalidates the data.
            try list.append(frame_owned_copy);
        }

        return try list.toOwnedSlice();
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
