const BinaryStream = @import("BinaryStream").BinaryStream;
const FullContainerName = @import("full-container-name.zig").FullContainerName;
const StackResponseSlotInfo = @import("stack-response-slot-info.zig").StackResponseSlotInfo;

pub const StackResponseContainerInfo = struct {
    container: FullContainerName,
    slotInfo: []const StackResponseSlotInfo,

    pub fn write(stream: *BinaryStream, value: StackResponseContainerInfo) !void {
        try FullContainerName.write(stream, value.container);
        try stream.writeVarInt(@intCast(value.slotInfo.len));
        for (value.slotInfo) |slot_info| {
            try StackResponseSlotInfo.write(stream, slot_info);
        }
    }
};
