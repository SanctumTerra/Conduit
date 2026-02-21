const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const RequestedResourcePack = @import("../types/requested-resource-pack.zig").RequestedResourcePack;
const ResourcePacksClientRequest = @import("../types/resource-packs-client-request.zig").ResourcePacksClientRequest;
const Packet = @import("../root.zig").Packet;
const ResourcePackResponse = @import("../root.zig").ResourcePackResponse;

pub const ResourcePackClientResponsePacket = struct {
    response: ResourcePackResponse,
    packs: []RequestedResourcePack,

    pub fn serialize(self: *ResourcePackClientResponsePacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ResourcePackResponse);

        try stream.writeUint8(@intFromEnum(self.response));
        try ResourcePacksClientRequest.write(stream, self.packs);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ResourcePackClientResponsePacket {
        _ = try stream.readVarInt();

        const response: ResourcePackResponse = @enumFromInt(try stream.readUint8());
        const packs = try ResourcePacksClientRequest.read(stream);

        return ResourcePackClientResponsePacket{
            .response = response,
            .packs = packs,
        };
    }

    pub fn deinit(self: *ResourcePackClientResponsePacket, allocator: std.mem.Allocator) void {
        for (self.packs) |*pack| {
            pack.deinit(allocator);
        }
        allocator.free(self.packs);
    }
};
