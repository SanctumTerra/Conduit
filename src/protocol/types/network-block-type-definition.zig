const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NBT = @import("nbt");

pub const NetworkBlockTypeDefinition = struct {
    identifier: []const u8,
    nbt: NBT.Tag,

    pub fn init(identifier: []const u8, nbt: NBT.Tag) NetworkBlockTypeDefinition {
        return NetworkBlockTypeDefinition{
            .identifier = identifier,
            .nbt = nbt,
        };
    }

    pub fn read(stream: *BinaryStream) ![]NetworkBlockTypeDefinition {
        const amount = try stream.readVarInt();
        const definitions = try stream.allocator.alloc(NetworkBlockTypeDefinition, @intCast(amount));

        for (0..@intCast(amount)) |i| {
            const identifier = try stream.readVarString();
            const nbt = try NBT.Tag.read(stream, stream.allocator, .{ .varint = true });

            definitions[i] = NetworkBlockTypeDefinition{
                .identifier = identifier,
                .nbt = nbt,
            };
        }

        return definitions;
    }

    pub fn write(stream: *BinaryStream, definitions: []const NetworkBlockTypeDefinition) !void {
        try stream.writeVarInt(@intCast(definitions.len));

        for (definitions) |definition| {
            try stream.writeVarString(definition.identifier);
            try definition.nbt.write(stream, .{ .varint = true });
        }
    }

    pub fn deinit(self: *NetworkBlockTypeDefinition, allocator: std.mem.Allocator) void {
        self.nbt.deinit(allocator);
    }
};
