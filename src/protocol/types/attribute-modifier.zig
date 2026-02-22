const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const AttributeModifier = struct {
    id: []const u8,
    name: []const u8,
    amount: f32,
    operation: i32,
    operand: i32,
    serializable: bool,

    pub fn init(id: []const u8, name: []const u8, amount: f32, operation: i32, operand: i32, serializable: bool) AttributeModifier {
        return .{
            .id = id,
            .name = name,
            .amount = amount,
            .operation = operation,
            .operand = operand,
            .serializable = serializable,
        };
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !AttributeModifier {
        const id = try stream.readString(allocator);
        const name = try stream.readString(allocator);
        const amount = try stream.readFloat32(.little);
        const operation = try stream.readInt32(.little);
        const operand = try stream.readInt32(.little);
        const serializable = try stream.readBool();

        return AttributeModifier{
            .id = id,
            .name = name,
            .amount = amount,
            .operation = operation,
            .operand = operand,
            .serializable = serializable,
        };
    }

    pub fn write(self: AttributeModifier, stream: *BinaryStream) !void {
        try stream.writeVarString(self.id);
        try stream.writeVarString(self.name);
        try stream.writeFloat32(self.amount, .Little);
        try stream.writeInt32(self.operation, .Little);
        try stream.writeInt32(self.operand, .Little);
        try stream.writeBool(self.serializable);
    }

    pub fn deinit(self: *AttributeModifier, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
    }
};
