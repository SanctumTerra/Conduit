const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const RequestedResourcePack = @import("requested-resource-pack.zig").RequestedResourcePack;

pub const ResourcePacksClientRequest = struct {
    pub fn read(stream: *BinaryStream) ![]RequestedResourcePack {
        const amount = try stream.readUint16(.Little);
        const packs = try stream.allocator.alloc(RequestedResourcePack, amount);

        for (0..amount) |i| {
            packs[i] = try RequestedResourcePack.read(stream);
        }

        return packs;
    }

    pub fn write(stream: *BinaryStream, packs: []const RequestedResourcePack) !void {
        try stream.writeUint16(@intCast(packs.len), .Little);

        for (packs) |pack| {
            try RequestedResourcePack.write(stream, pack);
        }
    }
};
