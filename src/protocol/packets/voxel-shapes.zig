const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const SerializableVoxelShape = @import("../types/serializable-voxel-shape.zig").SerializableVoxelShape;

pub const VoxelShapesPacket = struct {
    shapes: []SerializableVoxelShape,
    hashString: []const u8,
    registryHandle: u16,

    pub fn serialize(self: *VoxelShapesPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.VoxelShapes);

        try stream.writeVarInt(@intCast(self.shapes.len));
        for (self.shapes) |shape| {
            try SerializableVoxelShape.write(stream, shape);
        }

        try stream.writeVarString(self.hashString);
        try stream.writeInt16(@bitCast(self.registryHandle), .Little);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !VoxelShapesPacket {
        _ = try stream.readVarInt();

        const shapesLen = try stream.readVarInt();
        const shapes = try stream.allocator.alloc(SerializableVoxelShape, @intCast(shapesLen));

        for (0..@intCast(shapesLen)) |i| {
            shapes[i] = try SerializableVoxelShape.read(stream);
        }

        const hashString = try stream.readVarString();
        const registryHandle: u16 = @bitCast(try stream.readInt16(.Little));

        return VoxelShapesPacket{
            .shapes = shapes,
            .hashString = hashString,
            .registryHandle = registryHandle,
        };
    }

    pub fn deinit(self: *VoxelShapesPacket, allocator: std.mem.Allocator) void {
        for (self.shapes) |*shape| {
            shape.deinit(allocator);
        }
        allocator.free(self.shapes);
    }
};
