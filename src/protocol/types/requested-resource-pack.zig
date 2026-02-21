const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const RequestedResourcePack = struct {
    uuid: []const u8,
    version: []const u8,

    pub fn init(uuid: []const u8, version: []const u8) RequestedResourcePack {
        return RequestedResourcePack{
            .uuid = uuid,
            .version = version,
        };
    }

    pub fn read(stream: *BinaryStream) !RequestedResourcePack {
        const entry = try stream.readVarString();

        const separator_index = std.mem.indexOf(u8, entry, "_") orelse return error.InvalidPackEntry;

        const uuid = entry[0..separator_index];
        const version = entry[separator_index + 1 ..];

        return RequestedResourcePack{
            .uuid = uuid,
            .version = version,
        };
    }

    pub fn write(stream: *BinaryStream, pack: RequestedResourcePack) !void {
        const entry = try std.fmt.allocPrint(stream.allocator, "{s}_{s}", .{ pack.uuid, pack.version });
        defer stream.allocator.free(entry);

        try stream.writeVarString(entry);
    }

    pub fn deinit(self: *RequestedResourcePack, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
