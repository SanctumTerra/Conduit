const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const SerializableCells = struct {
    xSize: u8,
    ySize: u8,
    zSize: u8,
    storage: []u8,

    pub fn init(xSize: u8, ySize: u8, zSize: u8, storage: []u8) SerializableCells {
        return SerializableCells{
            .xSize = xSize,
            .ySize = ySize,
            .zSize = zSize,
            .storage = storage,
        };
    }

    pub fn read(stream: *BinaryStream) !SerializableCells {
        const xSize = try stream.readInt8();
        const ySize = try stream.readInt8();
        const zSize = try stream.readInt8();

        const length = try stream.readVarInt();
        const storage = try stream.allocator.alloc(u8, @intCast(length));

        for (0..@intCast(length)) |i| {
            storage[i] = @bitCast(try stream.readInt8());
        }

        return SerializableCells{
            .xSize = @bitCast(xSize),
            .ySize = @bitCast(ySize),
            .zSize = @bitCast(zSize),
            .storage = storage,
        };
    }

    pub fn write(stream: *BinaryStream, value: SerializableCells) !void {
        try stream.writeInt8(@bitCast(value.xSize));
        try stream.writeInt8(@bitCast(value.ySize));
        try stream.writeInt8(@bitCast(value.zSize));

        try stream.writeVarInt(@intCast(value.storage.len));
        for (value.storage) |cell| {
            try stream.writeInt8(@bitCast(cell));
        }
    }

    pub fn deinit(self: *SerializableCells, allocator: std.mem.Allocator) void {
        allocator.free(self.storage);
    }
};
