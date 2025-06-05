pub const PlayStatus = enum(i32) {
    LoginSuccess = 0,
    FailedClient = 1,
    FailedServer = 2,
    PlayerSpawn = 3,
    FailedInvalidTenant = 4,
    FailedVanillaEdu = 5,
    FailedIncompatible = 6,
    FailedServerFull = 7,
    FailedEditorVanillaMismatch = 8,
    FailedVanillaEditorMismatch = 9,
};
