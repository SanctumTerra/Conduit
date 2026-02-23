const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;
const ContainerId = @import("../enums/container-id.zig").ContainerId;
const ContainerType = @import("../enums/container-type.zig").ContainerType;

pub const ContainerOpenPacket = struct {
    identifier: ContainerId,
    container_type: ContainerType,
    position: BlockPosition,
    unique_id: i64,

    pub fn serialize(self: *const ContainerOpenPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ContainerOpen);
        try stream.writeUint8(@bitCast(@intFromEnum(self.identifier)));
        try stream.writeUint8(@bitCast(@intFromEnum(self.container_type)));
        try BlockPosition.write(stream, self.position);
        try stream.writeZigZong(self.unique_id);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ContainerOpenPacket {
        _ = try stream.readVarInt();
        const identifier_raw = try stream.readInt8();
        const container_type_raw = try stream.readInt8();
        const position = try BlockPosition.read(stream);
        const unique_id = try stream.readZigZong();
        return .{
            .identifier = std.meta.intToEnum(ContainerId, identifier_raw) catch return error.UnknownContainerId,
            .container_type = std.meta.intToEnum(ContainerType, container_type_raw) catch return error.UnknownContainerType,
            .position = position,
            .unique_id = unique_id,
        };
    }
};
