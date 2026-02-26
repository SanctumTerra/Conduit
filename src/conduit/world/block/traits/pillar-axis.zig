const trait_mod = @import("./trait.zig");

pub const State = struct {};

pub const PillarAxisTrait = trait_mod.BlockTrait(State, .{
    .identifier = "pillar_axis",
});
