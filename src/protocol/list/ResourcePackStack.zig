pub const ResourcePackIdVersion = struct {
    name: []const u8,
    uuid: []const u8,
    version: []const u8,
};

pub const ResourcePackStackPacket = struct {
    must_accept: bool,
    behavior_packs: std.ArrayList(ResourcePackIdVersion),
    resource_packs: std.ArrayList(ResourcePackIdVersion),
    game_version: []const u8,
    experiments: std.ArrayList(Experiment),
    experiments_previously_toggled: bool,
    has_editor_mode: bool,

    pub fn init(
        must_accept: bool,
        game_version: []const u8,
        experiments_previously_toggled: bool,
        has_editor_mode: bool,
    ) ResourcePackStackPacket {
        return .{
            .must_accept = must_accept,
            .behavior_packs = std.ArrayList(ResourcePackIdVersion).init(CAllocator.get()),
            .resource_packs = std.ArrayList(ResourcePackIdVersion).init(CAllocator.get()),
            .game_version = game_version,
            .experiments = std.ArrayList(Experiment).init(CAllocator.get()),
            .experiments_previously_toggled = experiments_previously_toggled,
            .has_editor_mode = has_editor_mode,
        };
    }

    pub fn deinit(self: *ResourcePackStackPacket) void {
        self.behavior_packs.deinit();
        self.resource_packs.deinit();
        self.experiments.deinit();
    }

    pub fn serialize(self: *ResourcePackStackPacket) ![]const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();

        stream.writeVarInt(Packets.ResourcePackStack);
        stream.writeBool(self.must_accept);

        stream.writeVarInt(@as(u32, @intCast(self.behavior_packs.items.len)));
        for (self.behavior_packs.items) |behavior_pack| {
            stream.writeVarString(behavior_pack.name);
            try stream.writeUuid(behavior_pack.uuid);
            stream.writeVarString(behavior_pack.version);
        }

        stream.writeVarInt(@as(u32, @intCast(self.resource_packs.items.len)));
        for (self.resource_packs.items) |resource_pack| {
            stream.writeVarString(resource_pack.name);
            try stream.writeUuid(resource_pack.uuid);
            stream.writeVarString(resource_pack.version);
        }

        stream.writeVarString(self.game_version);
        stream.writeInt32(@as(i32, @intCast(self.experiments.items.len)), .Big);
        for (self.experiments.items) |experiment| {
            stream.writeVarString(experiment.name);
            stream.writeBool(experiment.enabled);
        }

        stream.writeBool(self.experiments_previously_toggled);
        stream.writeBool(self.has_editor_mode);

        return stream.getBufferOwned(CAllocator.get());
    }
};

const std = @import("std");
const Experiment = @import("../types/Experiments.zig").Experiment;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const Packets = @import("../enums/Packets.zig").Packets;
const BinaryStream = @import("BinaryStream").BinaryStream;
