const BinaryStream = @import("BinaryStream").BinaryStream;
const ContainerName = @import("../enums/container-name.zig").ContainerName;

pub const FullContainerName = struct {
    identifier: ContainerName,
    dynamicIdentifier: ?u32,

    pub fn init(identifier: ContainerName, dynamicIdentifier: ?u32) FullContainerName {
        return FullContainerName{ .identifier = identifier, .dynamicIdentifier = dynamicIdentifier };
    }

    pub fn read(stream: *BinaryStream) !FullContainerName {
        const identifier: ContainerName = @enumFromInt(try stream.readUint8());
        const isDynamic = try stream.readBool();
        const dynamicIdentifier: ?u32 = if (isDynamic) try stream.readUint32(.Little) else null;
        return FullContainerName{ .identifier = identifier, .dynamicIdentifier = dynamicIdentifier };
    }

    pub fn write(stream: *BinaryStream, value: FullContainerName) !void {
        try stream.writeUint8(@intFromEnum(value.identifier));
        if (value.dynamicIdentifier) |dynId| {
            try stream.writeBool(true);
            try stream.writeUint32(dynId, .Little);
        } else {
            try stream.writeBool(false);
        }
    }
};
