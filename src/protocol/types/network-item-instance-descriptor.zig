const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ItemInstanceUserData = @import("item-instance-user-data.zig").ItemInstanceUserData;

pub const NetworkItemInstanceDescriptor = struct {
    network: i32,
    stackSize: ?u16,
    metadata: ?u32,
    networkBlockId: ?i32,
    extras: ?ItemInstanceUserData,

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !NetworkItemInstanceDescriptor {
        const network = try stream.readZigZag();
        if (network == 0) return .{
            .network = network,
            .stackSize = null,
            .metadata = null,
            .networkBlockId = null,
            .extras = null,
        };

        const stackSize = try stream.readUint16(.Little);
        const metadata = try stream.readVarInt();
        const networkBlockId = try stream.readZigZag();

        const length = try stream.readVarInt();
        const extras: ?ItemInstanceUserData = if (length > 0)
            try ItemInstanceUserData.read(stream, allocator, network)
        else
            null;

        return .{
            .network = network,
            .stackSize = stackSize,
            .metadata = metadata,
            .networkBlockId = networkBlockId,
            .extras = extras,
        };
    }

    pub fn write(stream: *BinaryStream, value: NetworkItemInstanceDescriptor, allocator: std.mem.Allocator) !void {
        try stream.writeZigZag(value.network);
        if (value.network == 0) return;

        try stream.writeUint16(value.stackSize orelse 0, .Little);
        try stream.writeVarInt(value.metadata orelse 0);
        try stream.writeZigZag(value.networkBlockId orelse 0);

        if (value.extras) |extras| {
            var sub = BinaryStream.init(allocator, null, null);
            defer sub.deinit();
            try ItemInstanceUserData.write(&sub, extras, value.network);
            const buf = sub.getBuffer();
            try stream.writeVarInt(@intCast(buf.len));
            try stream.write(buf);
        } else {
            try stream.writeVarInt(0);
        }
    }
};
