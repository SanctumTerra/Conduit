const std = @import("std");
const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;

pub const ResourcePackIdVersion = struct {
    name: []const u8,
    uuid: []const u8,
    version: []const u8,
};
pub const Experiment = struct {
    name: []const u8,
    enabled: bool,
};

pub const ResourcePackStackPacket = struct {
    must_accept: bool,
    behavior_packs: std.ArrayList(ResourcePackIdVersion),
    resource_packs: std.ArrayList(ResourcePackIdVersion),
    game_version: []const u8,
    experiments: std.ArrayList(Experiment),
    experiments_previously_toggled: bool,
    has_editor_mode: bool,

    pub fn init(must_accept: bool, game_version: []const u8, experiments_previously_toggled: bool, has_editor_mode: bool) ResourcePackStackPacket {
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

    pub fn serialize(self: *ResourcePackStackPacket) []const u8 {
        var stream = BinaryStream.init(&[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ResourcePackStack, .Big);
        stream.writeBool(self.must_accept);
        stream.writeVarInt(@as(u32, @intCast(self.behavior_packs.items.len)), .Big);

        for (self.behavior_packs.items) |behavior_pack| {
            stream.writeVarString(behavior_pack.name);
            stream.writeUUID(behavior_pack.uuid);
            stream.writeVarString(behavior_pack.version);
        }

        stream.writeVarInt(@as(u32, @intCast(self.resource_packs.items.len)), .Big);
        for (self.resource_packs.items) |resource_pack| {
            stream.writeVarString(resource_pack.name);
            stream.writeUUID(resource_pack.uuid);
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
        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for pong packet");
    }

    pub fn deserialize(data: []const u8) ResourcePackStackPacket {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        _ = stream.readVarInt(.Big);
        const must_accept = stream.readBool();
        const behavior_packs_len = stream.readVarInt(.Big);
        var behavior_packs = std.ArrayList(ResourcePackIdVersion).init(CAllocator.get());
        defer behavior_packs.deinit();
        for (0..behavior_packs_len) |_| {
            const name = stream.readVarString();
            const uuid = stream.readUUID();
            const version = stream.readVarString();
            behavior_packs.append(.{ .name = name, .uuid = uuid, .version = version });
        }
        const resource_packs_len = stream.readVarInt(.Big);
        var resource_packs = std.ArrayList(ResourcePackIdVersion).init(CAllocator.get());
        defer resource_packs.deinit();
        for (0..resource_packs_len) |_| {
            const name = stream.readVarString();
            const uuid = stream.readUUID();
            const version = stream.readVarString();
            resource_packs.append(.{ .name = name, .uuid = uuid, .version = version });
        }
        const game_version = stream.readVarString();
        const experiments_len = stream.readVarInt(.Big);
        var experiments = std.ArrayList(Experiment).init(CAllocator.get());
        defer experiments.deinit();
        for (0..experiments_len) |_| {
            const name = stream.readVarString();
            const enabled = stream.readBool();
            experiments.append(.{ .name = name, .enabled = enabled });
        }
        const experiments_previously_toggled = stream.readBool();
        const has_editor_mode = stream.readBool();
        return .{ .must_accept = must_accept, .behavior_packs = behavior_packs, .resource_packs = resource_packs, .game_version = game_version, .experiments = experiments, .experiments_previously_toggled = experiments_previously_toggled, .has_editor_mode = has_editor_mode };
    }
};
