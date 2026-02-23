const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const CompoundTag = @import("nbt").CompoundTag;

pub const ItemInstanceUserData = struct {
    nbt: ?CompoundTag,
    canPlaceOn: []const []const u8,
    canDestroy: []const []const u8,
    ticking: ?i64,

    pub fn deinit(self: *ItemInstanceUserData, allocator: std.mem.Allocator) void {
        if (self.nbt) |*nbt| nbt.deinit(allocator);
        for (self.canPlaceOn) |s| allocator.free(s);
        allocator.free(self.canPlaceOn);
        for (self.canDestroy) |s| allocator.free(s);
        allocator.free(self.canDestroy);
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator, networkId: i32) !ItemInstanceUserData {
        const marker = try stream.readUint16(.Little);

        var nbt: ?CompoundTag = null;
        if (marker == 0xFFFF) {
            const version = try stream.readUint8();
            switch (version) {
                1 => {
                    nbt = try CompoundTag.read(stream, allocator, .{
                        .name = false,
                        .tag_type = false,
                        .varint = false,
                        .endian = .Little,
                    });
                },
                else => return error.UnsupportedNbtVersion,
            }
        }

        const placeCount: u32 = @intCast(try stream.readInt32(.Little));
        const canPlaceOn = try allocator.alloc([]const u8, placeCount);
        for (0..placeCount) |i| {
            canPlaceOn[i] = try stream.readString32(.Little);
        }

        const destroyCount: u32 = @intCast(try stream.readInt32(.Little));
        const canDestroy = try allocator.alloc([]const u8, destroyCount);
        for (0..destroyCount) |i| {
            canDestroy[i] = try stream.readString32(.Little);
        }

        const ticking: ?i64 = if (networkId == @import("../root.zig").SHIELD_NETWORK_ID)
            try stream.readInt64(.Little)
        else
            null;

        return .{
            .nbt = nbt,
            .canPlaceOn = canPlaceOn,
            .canDestroy = canDestroy,
            .ticking = ticking,
        };
    }

    pub fn write(stream: *BinaryStream, value: ItemInstanceUserData, networkId: i32) !void {
        if (value.nbt) |*nbt| {
            try stream.writeUint16(0xFFFF, .Little);
            try stream.writeUint8(0x01);
            try CompoundTag.write(stream, nbt, .{
                .name = false,
                .tag_type = false,
                .varint = false,
                .endian = .Little,
            });
        } else {
            try stream.writeUint16(0x0000, .Little);
        }

        try stream.writeInt32(@intCast(value.canPlaceOn.len), .Little);
        for (value.canPlaceOn) |s| {
            try stream.writeString32(s, .Little);
        }

        try stream.writeInt32(@intCast(value.canDestroy.len), .Little);
        for (value.canDestroy) |s| {
            try stream.writeString32(s, .Little);
        }

        if (networkId == @import("../root.zig").SHIELD_NETWORK_ID) {
            try stream.writeInt64(value.ticking orelse 0, .Little);
        }
    }
};
