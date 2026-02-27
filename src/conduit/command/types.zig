pub const CommandArgValid: u32 = 0x100000;
pub const CommandArgEnum: u32 = 0x200000;
pub const CommandArgSoftEnum: u32 = 0x4000000;

pub const ParamType = enum(u32) {
    Int = 1,
    Float = 3,
    Value = 4,
    WildcardInt = 5,
    Operator = 6,
    CompareOperator = 7,
    Target = 8,
    WildcardTarget = 10,
    Filepath = 17,
    FullIntegerRange = 23,
    EquipmentSlot = 47,
    String = 48,
    BlockPosition = 64,
    Position = 65,
    Message = 67,
    RawText = 70,
    JSON = 74,
    BlockState = 84,
    Command = 87,
};

pub const CommandParameter = struct {
    name: []const u8,
    param_type: ParamType,
    optional: bool,
    options: u8 = 0,
    enum_index: ?u32 = null,
    soft_enum_index: ?u32 = null,

    pub fn computeTypeField(self: CommandParameter) u32 {
        if (self.enum_index) |idx| {
            return CommandArgValid | CommandArgEnum | idx;
        }
        if (self.soft_enum_index) |idx| {
            return CommandArgValid | CommandArgSoftEnum | idx;
        }
        return CommandArgValid | @intFromEnum(self.param_type);
    }
};

pub const CommandOverload = struct {
    params: []const CommandParameter,
    chaining: bool = false,
};

pub const CommandEnum = struct {
    name: []const u8,
    values: []const []const u8,
    owned: bool = false,
};

pub const SoftEnum = struct {
    name: []const u8,
    values: []const []const u8,
};
