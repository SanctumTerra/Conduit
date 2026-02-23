const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ItemInstanceUserData = @import("item-instance-user-data.zig").ItemInstanceUserData;

pub const NetworkItemStackDescriptor = struct {
    network: i32,
    stackSize: ?u16,
    metadata: ?u32,
    itemStackId: ?i32,
    networkBlockId: ?i32,
    extras: ?ItemInstanceUserData,

    pub fn deinit(self: *NetworkItemStackDescriptor, allocator: std.mem.Allocator) void {
        if (self.extras) |*extras| extras.deinit(allocator);
    }

    pub fn skip(stream: *BinaryStream) !void {
        const network = try stream.readZigZag();
        if (network == 0) return;
        _ = try stream.readUint16(.Little);
        _ = try stream.readVarInt();
        if (try stream.readBool()) _ = try stream.readZigZag();
        _ = try stream.readZigZag();
        const length = try stream.readVarInt();
        stream.offset += length;
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !NetworkItemStackDescriptor {
        const network = try stream.readZigZag();
        if (network == 0) return .{
            .network = network,
            .stackSize = null,
            .metadata = null,
            .itemStackId = null,
            .networkBlockId = null,
            .extras = null,
        };

        const stackSize = try stream.readUint16(.Little);
        const metadata = try stream.readVarInt();
        const itemStackId: ?i32 = if (try stream.readBool()) try stream.readZigZag() else null;
        const networkBlockId = try stream.readZigZag();

        const length = try stream.readVarInt();
        const extras: ?ItemInstanceUserData = if (length > 0) blk: {
            const start = stream.offset;
            const result = ItemInstanceUserData.read(stream, allocator, network) catch {
                stream.offset = start + length;
                break :blk null;
            };
            stream.offset = start + length;
            break :blk result;
        } else null;

        return .{
            .network = network,
            .stackSize = stackSize,
            .metadata = metadata,
            .itemStackId = itemStackId,
            .networkBlockId = networkBlockId,
            .extras = extras,
        };
    }

    pub fn write(stream: *BinaryStream, value: NetworkItemStackDescriptor, allocator: std.mem.Allocator) !void {
        try stream.writeZigZag(value.network);
        if (value.network == 0) return;

        try stream.writeUint16(value.stackSize orelse 0, .Little);
        try stream.writeVarInt(value.metadata orelse 0);

        if (value.itemStackId) |id| {
            try stream.writeBool(true);
            try stream.writeZigZag(id);
        } else {
            try stream.writeBool(false);
        }

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
