const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Uuid = @import("../types/uuid.zig").Uuid;
const ResourcePackDescriptor = @import("../types/resource-pack-descriptor.zig").ResourcePackDescriptor;
const Packet = @import("../root.zig").Packet;

pub const ResourcePacksInfoPacket = struct {
    mustAccept: bool,
    hasAddons: bool,
    hasScripts: bool,
    forceDisableVibrantVisuals: bool,
    worldTemplateUuid: []const u8,
    worldTemplateVersion: []const u8,
    packs: []ResourcePackDescriptor,

    pub fn serialize(self: *ResourcePacksInfoPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ResourcePackInfo);

        try stream.writeBool(self.mustAccept);
        try stream.writeBool(self.hasAddons);
        try stream.writeBool(self.hasScripts);
        try stream.writeBool(self.forceDisableVibrantVisuals);
        try Uuid.write(stream, self.worldTemplateUuid);
        try stream.writeVarString(self.worldTemplateVersion);
        try ResourcePackDescriptor.write(stream, self.packs);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ResourcePacksInfoPacket {
        _ = try stream.readVarInt();

        const mustAccept = try stream.readBool();
        const hasAddons = try stream.readBool();
        const hasScripts = try stream.readBool();
        const forceDisableVibrantVisuals = try stream.readBool();
        const worldTemplateUuid = try Uuid.read(stream);
        const worldTemplateVersion = try stream.readVarString();
        const packs = try ResourcePackDescriptor.read(stream);

        return ResourcePacksInfoPacket{
            .mustAccept = mustAccept,
            .hasAddons = hasAddons,
            .hasScripts = hasScripts,
            .forceDisableVibrantVisuals = forceDisableVibrantVisuals,
            .worldTemplateUuid = worldTemplateUuid,
            .worldTemplateVersion = worldTemplateVersion,
            .packs = packs,
        };
    }

    pub fn deinit(self: *ResourcePacksInfoPacket, allocator: std.mem.Allocator) void {
        for (self.packs) |*pack| {
            pack.deinit(allocator);
        }
        allocator.free(self.packs);
    }
};
