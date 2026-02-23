const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const ItemStackRequestType = @import("../types/item-stack-request.zig");

pub const ItemStackRequest = ItemStackRequestType.ItemStackRequest;
pub const StackRequestAction = ItemStackRequestType.StackRequestAction;
pub const StackRequestSlotInfo = ItemStackRequestType.StackRequestSlotInfo;

pub const ItemStackRequestPacket = struct {
    requests: []ItemStackRequest,

    pub fn deinit(self: *ItemStackRequestPacket, allocator: std.mem.Allocator) void {
        for (self.requests) |*req| {
            allocator.free(req.actions);
            allocator.free(req.filterStrings);
        }
        allocator.free(self.requests);
    }

    pub fn deserialize(stream: *BinaryStream) !ItemStackRequestPacket {
        _ = try stream.readVarInt();

        const count = try stream.readVarInt();
        var requests = try stream.allocator.alloc(ItemStackRequest, count);
        for (0..count) |i| {
            requests[i] = try ItemStackRequest.read(stream, stream.allocator);
        }

        return .{ .requests = requests };
    }
};
