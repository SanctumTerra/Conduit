const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const DataItem = @import("../types/data-item.zig").DataItem;
const NetworkItemStackDescriptor = @import("../types/network-item-stack-descriptor.zig").NetworkItemStackDescriptor;
const std = @import("std");

pub const AddItemActorPacket = struct {
    uniqueEntityId: i64,
    runtimeEntityId: u64,
    item: NetworkItemStackDescriptor,
    position: Vector3f,
    velocity: Vector3f = Vector3f.init(0, 0, 0),
    entityMetadata: []const DataItem = &[_]DataItem{},
    fromFishing: bool = false,

    pub fn serialize(self: *const AddItemActorPacket, stream: *BinaryStream, allocator: std.mem.Allocator) ![]const u8 {
        try stream.writeVarInt(Packet.AddItemActor);
        try stream.writeZigZong(self.uniqueEntityId);
        try stream.writeVarLong(self.runtimeEntityId);
        try NetworkItemStackDescriptor.write(stream, self.item, allocator);
        try Vector3f.write(stream, self.position);
        try Vector3f.write(stream, self.velocity);
        try stream.writeVarInt(@intCast(self.entityMetadata.len));
        for (self.entityMetadata) |item| {
            try item.write(stream);
        }
        try stream.writeUint8(if (self.fromFishing) 1 else 0);
        return stream.getBuffer();
    }
};
