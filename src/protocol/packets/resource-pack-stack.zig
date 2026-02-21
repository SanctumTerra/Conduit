const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ResourceIdVersions = @import("../types/resource-id-versions.zig").ResourceIdVersions;
const Experiments = @import("../types/experiments.zig").Experiments;
const Packet = @import("../root.zig").Packet;

pub const ResourcePackStackPacket = struct {
    mustAccept: bool,
    texturePacks: []ResourceIdVersions,
    gameVersion: []const u8,
    experiments: []Experiments,
    experimentsPreviouslyToggled: bool,
    hasEditorPacks: bool,

    pub fn serialize(self: *ResourcePackStackPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.ResourcePackStack);

        try stream.writeBool(self.mustAccept);
        try ResourceIdVersions.write(stream, self.texturePacks);
        try stream.writeVarString(self.gameVersion);
        try Experiments.write(stream, self.experiments);
        try stream.writeBool(self.experimentsPreviouslyToggled);
        try stream.writeBool(self.hasEditorPacks);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !ResourcePackStackPacket {
        _ = try stream.readVarInt();

        const mustAccept = try stream.readBool();
        const texturePacks = try ResourceIdVersions.read(stream);
        const gameVersion = try stream.readVarString();
        const experiments = try Experiments.read(stream);
        const experimentsPreviouslyToggled = try stream.readBool();
        const hasEditorPacks = try stream.readBool();

        return ResourcePackStackPacket{
            .mustAccept = mustAccept,
            .texturePacks = texturePacks,
            .gameVersion = gameVersion,
            .experiments = experiments,
            .experimentsPreviouslyToggled = experimentsPreviouslyToggled,
            .hasEditorPacks = hasEditorPacks,
        };
    }

    pub fn deinit(self: *ResourcePackStackPacket, allocator: std.mem.Allocator) void {
        for (self.texturePacks) |*pack| {
            pack.deinit(allocator);
        }
        allocator.free(self.texturePacks);

        for (self.experiments) |*experiment| {
            experiment.deinit(allocator);
        }
        allocator.free(self.experiments);
    }
};
