const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Uuid = @import("uuid.zig").Uuid;

pub const ResourcePackDescriptor = struct {
    uuid: []const u8,
    version: []const u8,
    size: u64,
    contentKey: []const u8,
    subpackName: []const u8,
    contentIdentity: []const u8,
    hasScripts: bool,
    isAddonPack: bool,
    hasRtxCapabilities: bool,
    cdnUrl: []const u8,

    pub fn init(
        uuid: []const u8,
        version: []const u8,
        size: u64,
        contentKey: []const u8,
        subpackName: []const u8,
        contentIdentity: []const u8,
        hasScripts: bool,
        isAddonPack: bool,
        hasRtxCapabilities: bool,
        cdnUrl: []const u8,
    ) ResourcePackDescriptor {
        return ResourcePackDescriptor{
            .uuid = uuid,
            .version = version,
            .size = size,
            .contentKey = contentKey,
            .subpackName = subpackName,
            .contentIdentity = contentIdentity,
            .hasScripts = hasScripts,
            .isAddonPack = isAddonPack,
            .hasRtxCapabilities = hasRtxCapabilities,
            .cdnUrl = cdnUrl,
        };
    }

    pub fn read(stream: *BinaryStream) ![]ResourcePackDescriptor {
        const amount = try stream.readInt16(.Little);
        const packs = try stream.allocator.alloc(ResourcePackDescriptor, @intCast(amount));

        for (0..@intCast(amount)) |i| {
            const uuid = try Uuid.read(stream);
            const version = try stream.readVarString();
            const size = try stream.readUint64(.Little);
            const contentKey = try stream.readVarString();
            const subpackName = try stream.readVarString();
            const contentIdentity = try stream.readVarString();
            const hasScripts = try stream.readBool();
            const isAddonPack = try stream.readBool();
            const hasRtxCapabilities = try stream.readBool();
            const cdnUrl = try stream.readVarString();

            packs[i] = ResourcePackDescriptor{
                .uuid = uuid,
                .version = version,
                .size = size,
                .contentKey = contentKey,
                .subpackName = subpackName,
                .contentIdentity = contentIdentity,
                .hasScripts = hasScripts,
                .isAddonPack = isAddonPack,
                .hasRtxCapabilities = hasRtxCapabilities,
                .cdnUrl = cdnUrl,
            };
        }

        return packs;
    }

    pub fn write(stream: *BinaryStream, packs: []const ResourcePackDescriptor) !void {
        try stream.writeInt16(@intCast(packs.len), .Little);

        for (packs) |pack| {
            try Uuid.write(stream, pack.uuid);
            try stream.writeVarString(pack.version);
            try stream.writeUint64(pack.size, .Little);
            try stream.writeVarString(pack.contentKey);
            try stream.writeVarString(pack.subpackName);
            try stream.writeVarString(pack.contentIdentity);
            try stream.writeBool(pack.hasScripts);
            try stream.writeBool(pack.isAddonPack);
            try stream.writeBool(pack.hasRtxCapabilities);
            try stream.writeVarString(pack.cdnUrl);
        }
    }

    pub fn deinit(self: *ResourcePackDescriptor, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
