const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const NBT = @import("nbt");

pub const ItemRegistryEntry = struct {
    identifier: []const u8,
    network_id: i16,
    is_component_based: bool,
    version: i32,
    properties: *const NBT.Tag,
};

pub const ItemRegistryPacket = struct {
    entries: []const ItemRegistryEntry,

    pub fn serialize(self: *const ItemRegistryPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ItemRegistry);
        try stream.writeVarInt(@intCast(self.entries.len));
        for (self.entries) |entry| {
            try stream.writeVarString(entry.identifier);
            try stream.writeInt16(entry.network_id, .Little);
            try stream.writeBool(entry.is_component_based);
            try stream.writeZigZag(entry.version);
            try entry.properties.write(stream, .{ .name = true, .tag_type = true, .varint = true });
        }
        return stream.getBuffer();
    }
};
