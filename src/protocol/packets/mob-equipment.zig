const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const ContainerId = @import("../root.zig").ContainerId;
const NetworkItemStackDescriptor = @import("../root.zig").NetworkItemStackDescriptor;

pub const MobEquipmentPacket = struct {
    runtime_entity_id: u64,
    item: NetworkItemStackDescriptor,
    slot: u8,
    selected_slot: u8,
    container_id: ContainerId,

    pub fn serialize(self: *const MobEquipmentPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.MobEquipment);
        try stream.writeVarLong(self.runtime_entity_id);
        try NetworkItemStackDescriptor.write(stream, self.item, stream.allocator);
        try stream.writeUint8(self.slot);
        try stream.writeUint8(self.selected_slot);
        try stream.writeInt8(@intFromEnum(self.container_id));
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !MobEquipmentPacket {
        _ = try stream.readVarInt();
        const runtime_entity_id = try stream.readVarLong();
        const item = try NetworkItemStackDescriptor.read(stream, stream.allocator);
        const slot = try stream.readUint8();
        const selected_slot = try stream.readUint8();
        const container_id_raw = try stream.readInt8();
        return .{
            .runtime_entity_id = runtime_entity_id,
            .item = item,
            .slot = slot,
            .selected_slot = selected_slot,
            .container_id = std.meta.intToEnum(ContainerId, container_id_raw) catch .None,
        };
    }
};
