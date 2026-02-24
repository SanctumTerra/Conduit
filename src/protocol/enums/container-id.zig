pub const ContainerId = enum(i8) {
    None = -1,
    Inventory = 0,
    First = 1,
    Last = 100,
    Offhand = 119,
    Armor = 120,
    SelectionSlots = 122,
    Ui = 124,
    Registry = 125,
    _,
};
