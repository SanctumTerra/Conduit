const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Frame = @import("../Frame.zig").Frame;
const CAllocator = @import("CAllocator");
const std = @import("std");
const Logger = @import("Logger").Logger;

pub const FrameSet = struct {
    sequence_number: u24,
    frames: []const Frame,

    pub fn init(sequence_number: u24, frames: []const Frame) FrameSet {
        return .{ .sequence_number = sequence_number, .frames = frames };
    }

    pub fn serialize(self: *const FrameSet) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        stream.writeUint8(Packets.FrameSet);
        stream.writeUint24(self.sequence_number, .Little);
        for (self.frames) |frame| {
            frame.write(&stream);
        }
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize FrameSet: {}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) FrameSet {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readUint8();
        const sequence_number = stream.readUint24(.Little);
        const end_position = stream.buffer.items.len;
        var frames = std.ArrayList(Frame).init(CAllocator.get());

        while (stream.position < end_position) {
            const frame = Frame.read(&stream);
            frames.append(frame) catch |err| {
                Logger.ERROR("Failed to append frame: {}", .{err});
                frames.deinit();
                return FrameSet.init(sequence_number, &[_]Frame{});
            };
            // defer frame.deinit();
        }

        return FrameSet.init(sequence_number, frames.toOwnedSlice() catch {
            Logger.ERROR("Failed to convert frames to owned slice", .{});
            frames.deinit();
            return FrameSet.init(sequence_number, &[_]Frame{});
        });
    }
};
