const std = @import("std");
const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const Events = @import("../../events/root.zig");

pub fn handleTextPacket(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const text = try Protocol.TextPacket.deserialize(stream);

    if (text.textType == .Chat) {
        const sender = network.conduit.getPlayerByConnection(connection) orelse return;

        if (std.mem.indexOf(u8, text.message, "generate") != null) {
            try generateChunks(network, sender);
            return;
        }

        var event = Events.types.PlayerChatEvent{
            .player = sender,
            .message = text.message,
        };
        if (!network.conduit.events.emit(.PlayerChat, &event)) return;

        var str = BinaryStream.init(network.allocator, null, null);
        defer str.deinit();

        var packet = Protocol.TextPacket{
            .textType = .Chat,
            .sourceName = sender.username,
            .message = event.message,
            .xuid = sender.xuid,
        };

        const serialized = try packet.serialize(&str);

        const snapshots = network.conduit.getPlayerSnapshots();
        for (snapshots) |p| {
            try network.sendPacket(p.connection, serialized);
        }
    }
}

const Dimension = @import("../../world/dimension/dimension.zig").Dimension;
const Task = @import("../../tasks.zig").Task;

const ChunkGenState = struct {
    dimension: *Dimension,
    cx: i32,
    cz: i32,
    radius: i32,
    count: u32,
    target: u32,
    start_time: i64,
    network: *NetworkHandler,
    connection: *Raknet.Connection,
};

fn chunkGenStep(ctx: *anyopaque) bool {
    const state: *ChunkGenState = @ptrCast(@alignCast(ctx));
    const batch: u32 = 16;
    var done: u32 = 0;

    while (done < batch and state.count < state.target) {
        _ = state.dimension.getOrCreateChunk(state.cx, state.cz) catch {};
        state.count += 1;
        done += 1;

        state.cz += 1;
        if (state.cz > state.radius) {
            state.cz = -state.radius;
            state.cx += 1;
            if (state.cx > state.radius) break;
        }
    }

    if (state.count >= state.target or state.cx > state.radius) {
        const elapsed = std.time.milliTimestamp() - state.start_time;
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "§aGenerated {d} chunks in {d}ms", .{ state.count, elapsed }) catch return true;

        var str = BinaryStream.init(state.network.allocator, null, null);
        defer str.deinit();
        var packet = Protocol.TextPacket{ .textType = .Raw, .message = msg };
        const serialized = packet.serialize(&str) catch return true;
        state.network.sendPacket(state.connection, serialized) catch {};

        state.network.allocator.destroy(state);
        return true;
    }
    return false;
}

fn generateChunks(network: *NetworkHandler, sender: anytype) !void {
    const world = network.conduit.getWorld("world") orelse return;
    const overworld = world.getDimension("overworld") orelse return;

    sendChat(network, sender, "§eQueued 100000 chunks for generation...");

    const state = try network.allocator.create(ChunkGenState);
    state.* = .{
        .dimension = overworld,
        .cx = -178,
        .cz = -178,
        .radius = 178,
        .count = 0,
        .target = 100000,
        .start_time = std.time.milliTimestamp(),
        .network = network,
        .connection = sender.connection,
    };

    try network.conduit.tasks.enqueue(.{
        .func = chunkGenStep,
        .ctx = @ptrCast(state),
        .name = "chunk_generation",
    });
}

fn sendChat(network: *NetworkHandler, player: anytype, message: []const u8) void {
    var str = BinaryStream.init(network.allocator, null, null);
    defer str.deinit();

    var packet = Protocol.TextPacket{
        .textType = .Raw,
        .message = message,
    };
    const serialized = packet.serialize(&str) catch return;
    network.sendPacket(player.connection, serialized) catch {};
}
