const trait_mod = @import("./trait.zig");

pub const State = struct {};

pub const CardinalDirectionTrait = trait_mod.BlockTrait(State, .{
    .identifier = "cardinal_direction",
});
