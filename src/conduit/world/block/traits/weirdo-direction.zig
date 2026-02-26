const trait_mod = @import("./trait.zig");

pub const State = struct {};

pub const WeirdoDirectionTrait = trait_mod.BlockTrait(State, .{
    .identifier = "weirdo_direction",
});
