const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;

pub const BlockPosition = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn init(x: i32, y: i32, z: i32) BlockPosition {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn serialize(self: *BlockPosition) []const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeZigZag(self.x);
        stream.writeVarInt(@as(u32, @intCast(self.y)));
        stream.writeZigZag(self.z);
        return stream.getBufferOwned(CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize BlockPosition: {any}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8, allocator: std.mem.Allocator) BlockPosition {
        var stream = BinaryStream.init(allocator, data, 0);
        defer stream.deinit();
        const x = stream.readZigZag();
        const y = stream.readVarInt(.Big);
        const z = stream.readZigZag();
        return .{ .x = x, .y = y, .z = z };
    }
};
