const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const ItemStackResponse = @import("../types/item-stack-response.zig").ItemStackResponse;
const StackResponseContainerInfo = @import("../types/stack-response-container-info.zig").StackResponseContainerInfo;
const StackResponseSlotInfo = @import("../types/stack-response-slot-info.zig").StackResponseSlotInfo;
const ContainerName = @import("../root.zig").ContainerName;
const FullContainerName = @import("../root.zig").FullContainerName;
const ItemStackResponseStatus = @import("../root.zig").ItemStackResponseStatus;

pub const ItemStackResponsePacket = struct {
    responses: []const ItemStackResponse,

    pub fn serialize(self: *const ItemStackResponsePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ItemStackResponse);
        try stream.writeVarInt(@intCast(self.responses.len));
        for (self.responses) |response| {
            try ItemStackResponse.write(stream, response);
        }
        return stream.getBuffer();
    }
};

test "item stack response status values match bedrock wire values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ItemStackResponseStatus.Success));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ItemStackResponseStatus.Error));
    try std.testing.expectEqual(@as(u8, 28), @intFromEnum(ItemStackResponseStatus.PlayerNotInCreativeMode));
    try std.testing.expectEqual(@as(u8, 55), @intFromEnum(ItemStackResponseStatus.CannotPlaceItem));
    try std.testing.expectEqual(@as(u8, 67), @intFromEnum(ItemStackResponseStatus.ScreenStackError));
}

test "successful item stack response serializes container updates" {
    const allocator = std.testing.allocator;

    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    const packet = ItemStackResponsePacket{
        .responses = &[_]ItemStackResponse{
            .{
                .status = .Success,
                .requestId = 42,
                .containerInfo = &[_]StackResponseContainerInfo{
                    .{
                        .container = FullContainerName.init(ContainerName.Inventory, null),
                        .slotInfo = &[_]StackResponseSlotInfo{
                            .{
                                .slot = 2,
                                .hotbarSlot = 2,
                                .count = 16,
                                .stackNetworkId = 9001,
                                .customName = "Test",
                                .filteredCustomName = "",
                                .durabilityCorrection = 7,
                            },
                        },
                    },
                },
            },
        },
    };

    const buf = try packet.serialize(&stream);
    var read_stream = BinaryStream.init(allocator, buf, null);
    defer read_stream.deinit();

    try std.testing.expectEqual(Packet.ItemStackResponse, try read_stream.readVarInt());
    try std.testing.expectEqual(@as(u32, 1), try read_stream.readVarInt());
    try std.testing.expectEqual(@as(u8, @intFromEnum(ItemStackResponseStatus.Success)), try read_stream.readUint8());
    try std.testing.expectEqual(@as(i32, 42), try read_stream.readZigZag());
    try std.testing.expectEqual(@as(u32, 1), try read_stream.readVarInt());
    try std.testing.expectEqual(ContainerName.Inventory, @as(ContainerName, @enumFromInt(try read_stream.readUint8())));
    try std.testing.expect(!(try read_stream.readBool()));
    try std.testing.expectEqual(@as(u32, 1), try read_stream.readVarInt());
    try std.testing.expectEqual(@as(u8, 2), try read_stream.readUint8());
    try std.testing.expectEqual(@as(u8, 2), try read_stream.readUint8());
    try std.testing.expectEqual(@as(u8, 16), try read_stream.readUint8());
    try std.testing.expectEqual(@as(i32, 9001), try read_stream.readZigZag());
    try std.testing.expectEqualStrings("Test", try read_stream.readVarString());
    try std.testing.expectEqualStrings("", try read_stream.readVarString());
    try std.testing.expectEqual(@as(i32, 7), try read_stream.readZigZag());
    try std.testing.expectEqual(buf.len, read_stream.offset);
}

test "error item stack response omits container updates" {
    const allocator = std.testing.allocator;

    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    const packet = ItemStackResponsePacket{
        .responses = &[_]ItemStackResponse{
            .{
                .status = .CannotPlaceItem,
                .requestId = 7,
                .containerInfo = &[_]StackResponseContainerInfo{
                    .{
                        .container = FullContainerName.init(ContainerName.Inventory, null),
                        .slotInfo = &[_]StackResponseSlotInfo{},
                    },
                },
            },
        },
    };

    const buf = try packet.serialize(&stream);
    var read_stream = BinaryStream.init(allocator, buf, null);
    defer read_stream.deinit();

    try std.testing.expectEqual(Packet.ItemStackResponse, try read_stream.readVarInt());
    try std.testing.expectEqual(@as(u32, 1), try read_stream.readVarInt());
    try std.testing.expectEqual(@as(u8, @intFromEnum(ItemStackResponseStatus.CannotPlaceItem)), try read_stream.readUint8());
    try std.testing.expectEqual(@as(i32, 7), try read_stream.readZigZag());
    try std.testing.expectEqual(buf.len, read_stream.offset);
}
