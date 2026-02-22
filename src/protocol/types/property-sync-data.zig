const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const PropertySyncData = struct {
    ints: []PropertyInt,
    floats: []PropertyFloat,
    allocator: std.mem.Allocator,

    pub const PropertyInt = struct {
        index: u32,
        value: i32,
    };

    pub const PropertyFloat = struct {
        index: u32,
        value: f32,
    };

    pub fn init(allocator: std.mem.Allocator) PropertySyncData {
        return .{
            .ints = &[_]PropertyInt{},
            .floats = &[_]PropertyFloat{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PropertySyncData) void {
        if (self.ints.len > 0) self.allocator.free(self.ints);
        if (self.floats.len > 0) self.allocator.free(self.floats);
    }

    pub fn write(self: PropertySyncData, stream: *BinaryStream) !void {
        try stream.writeVarInt(@intCast(self.ints.len));
        for (self.ints) |int| {
            try stream.writeVarInt(int.index);
            try stream.writeZigZag(int.value);
        }

        try stream.writeVarInt(@intCast(self.floats.len));
        for (self.floats) |float| {
            try stream.writeVarInt(float.index);
            try stream.writeFloat32(float.value, .Little);
        }
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !PropertySyncData {
        const int_count = try stream.readVarInt();
        const ints = try allocator.alloc(PropertyInt, @intCast(int_count));
        errdefer allocator.free(ints);

        var i: usize = 0;
        while (i < int_count) : (i += 1) {
            ints[i] = .{
                .index = @intCast(try stream.readVarInt()),
                .value = try stream.readZigZag(),
            };
        }

        const float_count = try stream.readVarInt();
        const floats = try allocator.alloc(PropertyFloat, @intCast(float_count));
        errdefer allocator.free(floats);

        i = 0;
        while (i < float_count) : (i += 1) {
            floats[i] = .{
                .index = @intCast(try stream.readVarInt()),
                .value = try stream.readFloat32(.Little),
            };
        }

        return PropertySyncData{
            .ints = ints,
            .floats = floats,
            .allocator = allocator,
        };
    }
};
