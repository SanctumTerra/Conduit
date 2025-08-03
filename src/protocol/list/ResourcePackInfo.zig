pub const TexturePack = struct {
    name: []const u8,
};

pub const ResourcePackInfo = struct {
    must_accept: bool,
    hasAddons: bool,
    hasScripts: bool,
    vibrantVisualsDisabled: bool,
    worldTemplateUUID: []const u8,
    worldTemplateVersion: []const u8,
    texture_packs: std.ArrayList(TexturePack),

    pub fn init(must_accept: bool, hasAddons: bool, hasScripts: bool, vibrantVisualsDisabled: bool, worldTemplateUUID: []const u8, worldTemplateVersion: []const u8) ResourcePackInfo {
        return .{
            .must_accept = must_accept,
            .hasAddons = hasAddons,
            .vibrantVisualsDisabled = vibrantVisualsDisabled,
            .hasScripts = hasScripts,
            .worldTemplateUUID = worldTemplateUUID,
            .worldTemplateVersion = worldTemplateVersion,
            .texture_packs = std.ArrayList(TexturePack).init(CAllocator.get()),
        };
    }

    pub fn deinit(self: ResourcePackInfo) void {
        self.texture_packs.deinit();
    }

    pub fn serialize(self: *ResourcePackInfo) []const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ResourcePackInfo);
        stream.writeBool(self.must_accept);
        stream.writeBool(self.hasAddons);
        stream.writeBool(self.hasScripts);
        stream.writeBool(self.vibrantVisualsDisabled);
        stream.writeUuid(self.worldTemplateUUID) catch |err| {
            Logger.ERROR("Failed to serialize ResourcePackInfo: {any}", .{err});
            return &[_]u8{};
        };
        stream.writeVarString(self.worldTemplateVersion);

        stream.writeUint16(@as(u16, @intCast(self.texture_packs.items.len)), .Big);
        // TODO! Set up Resource Packs.
        // for (self.texture_packs.items) |texture_pack| {
        // _ = texture_pack;
        // stream.writeString(texture_pack.name);
        // }

        return stream.getBufferOwned(CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize ResourcePackInfo: {any}", .{err});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) !ResourcePackInfo {
        var stream = BinaryStream.init(CAllocator.get(), data, 0);
        defer stream.deinit();

        // Skip packet ID as it's already been read
        _ = stream.readVarInt();

        const must_accept = stream.readBool();
        const hasAddons = stream.readBool();
        const hasScripts = stream.readBool();
        const vibrantVisualsDisabled = stream.readBool();
        const worldTemplateUUID = stream.readUuid();
        const worldTemplateVersion = try stream.readVarString(CAllocator.get());

        const resource_pack_info = ResourcePackInfo.init(
            must_accept,
            hasAddons,
            hasScripts,
            vibrantVisualsDisabled,
            worldTemplateUUID,
            worldTemplateVersion,
        );

        const texture_pack_count = stream.readUint16(.Big);

        // TODO! Implement texture pack deserialization when serialize is complete
        // for (0..texture_pack_count) |_| {
        //     const name = try stream.readString(CAllocator.get());
        //     const texture_pack = TexturePack{ .name = name };
        //     try resource_pack_info.texture_packs.append(texture_pack);
        // }
        _ = texture_pack_count; // Suppress unused variable warning

        return resource_pack_info;
    }
};

const std = @import("std");
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const Packets = @import("../enums/Packets.zig").Packets;
const BinaryStream = @import("BinaryStream").BinaryStream;
