const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const ContainerId = @import("../enums/container-id.zig").ContainerId;
const ContainerType = @import("../enums/container-type.zig").ContainerType;

pub const ContainerClosePacket = struct {
    identifier: ContainerId,
    container_type: ContainerType,
    server_initiated: bool,

    pub fn serialize(self: *const ContainerClosePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ContainerClose);
        try stream.writeInt8(@intFromEnum(self.identifier));
        try stream.writeInt8(@intFromEnum(self.container_type));
        try stream.writeBool(self.server_initiated);
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ContainerClosePacket {
        _ = try stream.readVarInt();
        const identifier_raw = try stream.readInt8();
        const container_type_raw = try stream.readInt8();
        const server_initiated = try stream.readBool();
        return .{
            .identifier = std.meta.intToEnum(ContainerId, identifier_raw) catch return error.UnknownContainerId,
            .container_type = std.meta.intToEnum(ContainerType, container_type_raw) catch return error.UnknownContainerType,
            .server_initiated = server_initiated,
        };
    }
};
