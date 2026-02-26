const trait_mod = @import("./trait.zig");

pub const State = struct {};

pub const VerticalHalfTrait = trait_mod.BlockTrait(State, .{
    .identifier = "vertical_half",
});
