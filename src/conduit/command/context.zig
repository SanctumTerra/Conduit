const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Player = @import("../player/player.zig").Player;
const NetworkHandler = @import("../network/network-handler.zig").NetworkHandler;

pub const CommandContext = struct {
    player: *Player,
    args: []const u8,
    network: *NetworkHandler,
    allocator: std.mem.Allocator,

    origin_type: []const u8 = "player",
    uuid: [16]u8 = .{0} ** 16,
    request_id: []const u8 = "",

    single_target_buf: [1]*Player = undefined,

    pub fn sendOutput(self: *CommandContext, success: bool, message: []const u8) void {
        var stream = BinaryStream.init(self.allocator, null, null);
        defer stream.deinit();

        const msgs = [_]Protocol.CommandOutputMessage{
            .{ .success = success, .message = message, .parameters = &.{} },
        };

        var output = Protocol.CommandOutputPacket{
            .origin_type = self.origin_type,
            .uuid = self.uuid,
            .request_id = self.request_id,
            .player_unique_id = self.player.entity.runtime_id,
            .output_type = "alloutput",
            .success_count = if (success) 1 else 0,
            .messages = &msgs,
        };

        const serialized = output.serialize(&stream) catch return;
        self.network.sendPacket(self.player.connection, serialized) catch {};
    }

    pub fn resolvePlayer(self: *CommandContext, name: []const u8) ?*Player {
        if (name.len > 0 and name[0] == '@') return self.resolveSelector(name);
        const snapshots = self.network.conduit.getPlayerSnapshots();
        for (snapshots) |player| {
            if (std.ascii.eqlIgnoreCase(player.username, name)) return player;
        }
        return null;
    }

    pub fn resolvePlayers(self: *CommandContext, name: []const u8) ?[]*Player {
        if (name.len >= 2 and name[0] == '@') {
            const kind = name[1];
            if (kind == 'a' or kind == 'e') {
                const snapshots = self.network.conduit.getPlayerSnapshots();
                if (snapshots.len == 0) return null;
                return snapshots;
            }
        }
        const single = self.resolvePlayer(name) orelse return null;
        self.single_target_buf = .{single};
        return &self.single_target_buf;
    }

    pub fn resolveSelector(self: *CommandContext, selector: []const u8) ?*Player {
        if (selector.len < 2 or selector[0] != '@') return null;
        const kind = selector[1];
        return switch (kind) {
            's' => self.player,
            'p' => self.nearestPlayer(),
            'r' => self.randomPlayer(),
            'a', 'e' => self.player,
            else => null,
        };
    }

    fn nearestPlayer(self: *CommandContext) ?*Player {
        const snapshots = self.network.conduit.getPlayerSnapshots();
        var best: ?*Player = null;
        var best_dist: f32 = std.math.inf(f32);
        for (snapshots) |player| {
            if (!player.spawned) continue;
            const dist = self.player.entity.position.distance(player.entity.position);
            if (dist < best_dist) {
                best_dist = dist;
                best = player;
            }
        }
        return best;
    }

    fn randomPlayer(self: *CommandContext) ?*Player {
        const snapshots = self.network.conduit.getPlayerSnapshots();
        if (snapshots.len == 0) return null;
        var spawned_count: usize = 0;
        for (snapshots) |p| {
            if (p.spawned) spawned_count += 1;
        }
        if (spawned_count == 0) return null;
        const seed: u64 = @bitCast(std.time.milliTimestamp());
        const idx = seed % spawned_count;
        var i: usize = 0;
        for (snapshots) |p| {
            if (!p.spawned) continue;
            if (i == idx) return p;
            i += 1;
        }
        return snapshots[0];
    }

    pub fn parseCoord(str: []const u8, current: f32) ?f32 {
        if (str.len == 0) return null;
        if (str[0] == '~') {
            if (str.len == 1) return current;
            const offset = std.fmt.parseFloat(f32, str[1..]) catch return null;
            return current + offset;
        }
        return std.fmt.parseFloat(f32, str) catch null;
    }
};
