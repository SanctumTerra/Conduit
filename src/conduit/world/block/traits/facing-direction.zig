const trait_mod = @import("./trait.zig");

pub const State = struct {};

pub const FacingDirectionTrait = trait_mod.BlockTrait(State, .{
    .identifier = "facing_direction",
});
