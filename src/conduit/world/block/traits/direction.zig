const trait_mod = @import("./trait.zig");

pub const State = struct {};

pub const DirectionTrait = trait_mod.BlockTrait(State, .{
    .identifier = "direction",
});
