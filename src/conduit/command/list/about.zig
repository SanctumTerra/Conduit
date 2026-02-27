const Command = @import("../command.zig").Command;
const CommandContext = @import("../context.zig").CommandContext;
const CommandRegistry = @import("../registry.zig").CommandRegistry;

pub const version = "0.1.0";

pub fn register(registry: *CommandRegistry) !void {
    const cmd = try Command.init(
        registry.allocator,
        "about",
        "Show server information",
        "",
        &.{},
        @ptrCast(&handle),
    );
    try registry.registerCommand(cmd);
}

fn handle(raw: *anyopaque) void {
    const ctx: *CommandContext = @ptrCast(@alignCast(raw));
    ctx.sendOutput(
        true,
        "\xc2\xa77--------- \xc2\xa7bConduit \xc2\xa77---------\n" ++
            "\xc2\xa7fA Minecraft Bedrock server written in \xc2\xa76Zig\n" ++
            "\xc2\xa77Version: \xc2\xa7a" ++ version ++ "\n" ++
            "\xc2\xa77GitHub: \xc2\xa7bhttps://github.com/SanctumTerra/Conduit",
    );
}
