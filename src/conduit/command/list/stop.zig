const Raknet = @import("Raknet");
const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;

pub fn register(registry: *CommandRegistry) !void {
    const cmd = try Command.init(
        registry.allocator,
        "stop",
        "Stop the server",
        "conduit.command.stop",
        &.{},
        @ptrCast(&handle),
    );
    try registry.registerCommand(cmd);
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    ctx.sendOutput(true, "\xc2\xa7cStopping server...");
    Raknet.Logger.INFO("Server stop requested by {s}", .{ctx.player.username});
    const conduit = ctx.network.conduit;
    conduit.stop() catch {};
    conduit.raknet.running = false;
}
