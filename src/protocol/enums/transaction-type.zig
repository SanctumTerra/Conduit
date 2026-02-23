pub const TransactionType = enum(u32) {
    Normal = 0,
    Mismatch = 1,
    UseItem = 2,
    UseItemOnEntity = 3,
    ReleaseItem = 4,
};
