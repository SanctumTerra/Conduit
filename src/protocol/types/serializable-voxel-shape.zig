const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const SerializableCells = @import("./serializable-cells.zig").SerializableCells;

pub const SerializableVoxelShape = struct {
    cells: SerializableCells,
    xCoordinates: []f32,
    yCoordinates: []f32,
    zCoordinates: []f32,

    pub fn init(
        cells: SerializableCells,
        xCoordinates: []f32,
        yCoordinates: []f32,
        zCoordinates: []f32,
    ) SerializableVoxelShape {
        return SerializableVoxelShape{
            .cells = cells,
            .xCoordinates = xCoordinates,
            .yCoordinates = yCoordinates,
            .zCoordinates = zCoordinates,
        };
    }

    pub fn read(stream: *BinaryStream) !SerializableVoxelShape {
        const cells = try SerializableCells.read(stream);

        const xLength = try stream.readVarInt();
        const xCoordinates = try stream.allocator.alloc(f32, @intCast(xLength));
        for (0..@intCast(xLength)) |i| {
            xCoordinates[i] = try stream.readFloat32(.Little);
        }

        const yLength = try stream.readVarInt();
        const yCoordinates = try stream.allocator.alloc(f32, @intCast(yLength));
        for (0..@intCast(yLength)) |i| {
            yCoordinates[i] = try stream.readFloat32(.Little);
        }

        const zLength = try stream.readVarInt();
        const zCoordinates = try stream.allocator.alloc(f32, @intCast(zLength));
        for (0..@intCast(zLength)) |i| {
            zCoordinates[i] = try stream.readFloat32(.Little);
        }

        return SerializableVoxelShape{
            .cells = cells,
            .xCoordinates = xCoordinates,
            .yCoordinates = yCoordinates,
            .zCoordinates = zCoordinates,
        };
    }

    pub fn write(stream: *BinaryStream, value: SerializableVoxelShape) !void {
        try SerializableCells.write(stream, value.cells);

        try stream.writeVarInt(@intCast(value.xCoordinates.len));
        for (value.xCoordinates) |x| {
            try stream.writeFloat32(x, .Little);
        }

        try stream.writeVarInt(@intCast(value.yCoordinates.len));
        for (value.yCoordinates) |y| {
            try stream.writeFloat32(y, .Little);
        }

        try stream.writeVarInt(@intCast(value.zCoordinates.len));
        for (value.zCoordinates) |z| {
            try stream.writeFloat32(z, .Little);
        }
    }

    pub fn deinit(self: *SerializableVoxelShape, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        allocator.free(self.xCoordinates);
        allocator.free(self.yCoordinates);
        allocator.free(self.zCoordinates);
    }
};
