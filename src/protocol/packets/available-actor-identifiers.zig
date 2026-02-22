const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const NBT = @import("nbt");
const Packet = @import("../root.zig").Packet;

pub const AvailableActorIdentifiersPacket = struct {
    data: NBT.CompoundTag,

    pub fn serialize(self: *AvailableActorIdentifiersPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.AvailableActorIdentifiers);
        try NBT.CompoundTag.write(stream, &self.data, .{ .varint = true });
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !AvailableActorIdentifiersPacket {
        _ = try stream.readVarInt();
        const data = try NBT.CompoundTag.read(stream, stream.allocator, .{ .varint = true });

        return AvailableActorIdentifiersPacket{
            .data = data,
        };
    }

    pub fn deinit(self: *AvailableActorIdentifiersPacket, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }
};
