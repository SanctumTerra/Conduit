pub const ResourcePackResponse = enum(u8) {
    None = 0,
    Refused = 1,
    SendPacks = 2,
    HaveAllPacks = 3,
    Completed = 4,
};
