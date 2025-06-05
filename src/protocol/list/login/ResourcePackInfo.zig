const std = @import("std");
const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const TexturePack = struct {
    name: []const u8,
};
pub const ResourcePackInfo = struct {
    must_accept: bool,
    hasAddons: bool,
    hasScripts: bool,
    worldTemplateUUID: []const u8,
    worldTemplateVersion: []const u8,
    texture_packs: std.ArrayList(TexturePack),

    pub fn init(must_accept: bool, hasAddons: bool, hasScripts: bool, worldTemplateUUID: []const u8, worldTemplateVersion: []const u8) ResourcePackInfo {
        return .{ .must_accept = must_accept, .hasAddons = hasAddons, .hasScripts = hasScripts, .worldTemplateUUID = worldTemplateUUID, .worldTemplateVersion = worldTemplateVersion, .texture_packs = std.ArrayList(TexturePack).init(CAllocator.get()) };
    }

    pub fn serialize(self: *ResourcePackInfo) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ResourcePackInfo, .Big);
        stream.writeBool(self.must_accept);
        stream.writeBool(self.hasAddons);
        stream.writeBool(self.hasScripts);
        stream.writeUUID(self.worldTemplateUUID);
        stream.writeVarString(self.worldTemplateVersion);

        stream.writeUint16(@as(u16, @intCast(self.texture_packs.items.len)), .Big);
        // TODO! Set up Resource Packs.
        // for (self.texture_packs.items) |texture_pack| {
        // _ = texture_pack;
        // stream.writeString(texture_pack.name);
        // }

        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for pong packet");
    }

    pub fn deserialize(data: []const u8) ResourcePackInfo {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readVarInt(.Big);
        const must_accept = stream.readBool();
        const hasAddons = stream.readBool();
        const hasScripts = stream.readBool();
        const worldTemplateUUID = stream.readUUID();
        const worldTemplateVersion = stream.readString32(.Little);
        _ = stream.readUint16(.Big);
        // TODO! Set up Resource Packs.
        var texture_packs = std.ArrayList(TexturePack).init(CAllocator.get());
        defer texture_packs.deinit();
        return .{ .must_accept = must_accept, .hasAddons = hasAddons, .hasScripts = hasScripts, .worldTemplateUUID = worldTemplateUUID, .worldTemplateVersion = worldTemplateVersion, .texture_packs = texture_packs };
    }
};
