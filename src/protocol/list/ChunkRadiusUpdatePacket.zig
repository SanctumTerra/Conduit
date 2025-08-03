pub const ChunkRadiusUpdatePacket = struct {
    const Self = @This();
    radius: i32,

    pub fn init(radius: i32) ChunkRadiusUpdatePacket {
        return ChunkRadiusUpdatePacket{ .radius = radius };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn serialize(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var stream = BinaryStream.init(allocator, null, null);
        defer stream.deinit();
        stream.writeVarInt(Packets.ChunkRadiusUpdate);
        stream.writeZigZag(self.radius);
        return stream.getBufferOwned(CAllocator.get());
    }
};

const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const Packets = @import("../enums/Packets.zig").Packets;
const std = @import("std");
