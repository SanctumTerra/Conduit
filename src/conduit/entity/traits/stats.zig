const std = @import("std");
const builtin = @import("builtin");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Entity = @import("../entity.zig").Entity;
const EntityTrait = @import("./trait.zig").EntityTrait;
const Player = @import("../../player/player.zig").Player;
const Conduit = @import("../../conduit.zig").Conduit;

const is_windows = builtin.os.tag == .windows;

const PROCESS_MEMORY_COUNTERS = extern struct {
    cb: u32,
    PageFaultCount: u32,
    PeakWorkingSetSize: usize,
    WorkingSetSize: usize,
    QuotaPeakPagedPoolUsage: usize,
    QuotaPagedPoolUsage: usize,
    QuotaPeakNonPagedPoolUsage: usize,
    QuotaNonPagedPoolUsage: usize,
    PagefileUsage: usize,
    PeakPagefileUsage: usize,
};

const Psapi = if (is_windows) struct {
    extern "psapi" fn GetProcessMemoryInfo(hProcess: std.os.windows.HANDLE, ppsmemCounters: *PROCESS_MEMORY_COUNTERS, cb: u32) callconv(.winapi) i32;
} else struct {};

fn getMemoryMB() f64 {
    if (comptime is_windows) {
        var counters: PROCESS_MEMORY_COUNTERS = std.mem.zeroes(PROCESS_MEMORY_COUNTERS);
        counters.cb = @sizeOf(PROCESS_MEMORY_COUNTERS);
        const handle: std.os.windows.HANDLE = @ptrFromInt(@as(usize, 0xFFFFFFFFFFFFFFFF));
        if (Psapi.GetProcessMemoryInfo(handle, &counters, @sizeOf(PROCESS_MEMORY_COUNTERS)) != 0) {
            return @as(f64, @floatFromInt(counters.WorkingSetSize)) / (1024.0 * 1024.0);
        }
        return 0;
    } else {
        const file = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
        defer file.close();
        var buf: [128]u8 = undefined;
        const len = file.read(&buf) catch return 0;
        const content = buf[0..len];
        var iter = std.mem.splitScalar(u8, content, ' ');
        _ = iter.next();
        const rss_str = iter.next() orelse return 0;
        const rss_pages = std.fmt.parseInt(usize, rss_str, 10) catch return 0;
        return @as(f64, @floatFromInt(rss_pages * std.heap.page_size)) / (1024.0 * 1024.0);
    }
}

pub const State = struct {
    tick_count: u64,
};

fn getPlayer(entity: *Entity) ?*Player {
    if (!std.mem.eql(u8, entity.entity_type.identifier, "minecraft:player")) return null;
    return @fieldParentPtr("entity", entity);
}

fn onTick(state: *State, entity: *Entity) void {
    state.tick_count += 1;
    if (state.tick_count % 20 != 0) return;

    const player = getPlayer(entity) orelse return;
    const tps = player.network.conduit.current_tps;
    const mem = getMemoryMB();
    const tasks = player.network.conduit.tasks.pending();

    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "§aTPS: §f{d:.1} §8| §aMem: §f{d:.1}MB §8| §aTasks: §f{d}", .{ tps, mem, tasks }) catch return;

    var stream = BinaryStream.init(player.entity.allocator, null, null);
    defer stream.deinit();

    var packet = Protocol.TextPacket{
        .textType = .Tip,
        .message = text,
    };
    const serialized = packet.serialize(&stream) catch return;
    player.network.sendPacket(player.connection, serialized) catch {};
}

pub const StatsTrait = EntityTrait(State, .{
    .identifier = "stats",
    .onTick = onTick,
});
