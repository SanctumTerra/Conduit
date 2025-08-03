pub const PlayStatus = enum(i32) {
    LoginSuccess,
    FailedClient,
    FailedServer,
    PlayerSpawn,
    FailedInvalidTenant,
    FailedVanillaEdu,
    FailedIncompatible,
    FailedServerFull,
    FailedEditorVanillaMismatch,
    FailedVanillaEditorMismatch,
};
