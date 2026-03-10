const BinaryStream = @import("BinaryStream").BinaryStream;

pub const StackResponseSlotInfo = struct {
    slot: u8,
    hotbarSlot: u8,
    count: u8,
    stackNetworkId: i32,
    customName: []const u8,
    filteredCustomName: []const u8,
    durabilityCorrection: i32,

    pub fn write(stream: *BinaryStream, value: StackResponseSlotInfo) !void {
        try stream.writeUint8(value.slot);
        try stream.writeUint8(value.hotbarSlot);
        try stream.writeUint8(value.count);
        try stream.writeZigZag(value.stackNetworkId);
        try stream.writeVarString(value.customName);
        try stream.writeVarString(value.filteredCustomName);
        try stream.writeZigZag(value.durabilityCorrection);
    }
};
