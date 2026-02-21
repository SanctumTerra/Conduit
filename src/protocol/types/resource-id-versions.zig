const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const ResourceIdVersions = struct {
    name: []const u8,
    uuid: []const u8,
    version: []const u8,

    pub fn init(name: []const u8, uuid: []const u8, version: []const u8) ResourceIdVersions {
        return ResourceIdVersions{
            .name = name,
            .uuid = uuid,
            .version = version,
        };
    }

    pub fn read(stream: *BinaryStream) ![]ResourceIdVersions {
        const amount = try stream.readVarInt();
        const packs = try stream.allocator.alloc(ResourceIdVersions, @intCast(amount));

        for (0..@intCast(amount)) |i| {
            const uuid = try stream.readVarString();
            const version = try stream.readVarString();
            const name = try stream.readVarString();

            packs[i] = ResourceIdVersions{
                .name = name,
                .uuid = uuid,
                .version = version,
            };
        }

        return packs;
    }

    pub fn write(stream: *BinaryStream, packs: []const ResourceIdVersions) !void {
        try stream.writeVarInt(@intCast(packs.len));

        for (packs) |pack| {
            try stream.writeVarString(pack.uuid);
            try stream.writeVarString(pack.version);
            try stream.writeVarString(pack.name);
        }
    }

    pub fn deinit(self: *ResourceIdVersions, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
