const AbilityIndex = @import("../enums/ability-index.zig").AbilityIndex;

pub const AbilitySet = struct {
    ability: AbilityIndex,
    value: bool,
};
