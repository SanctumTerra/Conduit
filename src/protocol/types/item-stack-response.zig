const BinaryStream = @import("BinaryStream").BinaryStream;
const ItemStackResponseStatus = @import("../enums/item-stack-response-status.zig").ItemStackResponseStatus;
const StackResponseContainerInfo = @import("stack-response-container-info.zig").StackResponseContainerInfo;

pub const ItemStackResponse = struct {
    status: ItemStackResponseStatus,
    requestId: i32,
    containerInfo: []const StackResponseContainerInfo,

    pub fn write(stream: *BinaryStream, value: ItemStackResponse) !void {
        try stream.writeUint8(@intFromEnum(value.status));
        try stream.writeZigZag(value.requestId);
        if (value.status == .Success) {
            try stream.writeVarInt(@intCast(value.containerInfo.len));
            for (value.containerInfo) |container_info| {
                try StackResponseContainerInfo.write(stream, container_info);
            }
        }
    }
};
