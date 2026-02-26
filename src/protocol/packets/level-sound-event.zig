const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;

pub const LevelSoundEvent = enum(u32) {
    DoorOpen = 7,
    DoorClose = 8,
    TrapdoorOpen = 9,
    TrapdoorClose = 10,
    FenceGateOpen = 11,
    FenceGateClose = 12,
    ChestOpen = 67,
    ChestClosed = 68,
    ShulkerBoxOpen = 69,
    ShulkerBoxClosed = 70,
    EnderChestOpen = 71,
    EnderChestClosed = 72,
    BarrelOpen = 270,
    BarrelClose = 271,
    _,
};

pub const LevelSoundEventPacket = struct {
    event: LevelSoundEvent,
    position: Vector3f,
    data: i32,
    actorIdentifier: []const u8,
    isBabyMob: bool,
    isGlobal: bool,
    uniqueActorId: i64 = -1,

    pub fn serialize(self: *const LevelSoundEventPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.LevelSoundEvent);
        try stream.writeVarInt(@intFromEnum(self.event));
        try Vector3f.write(stream, self.position);
        try stream.writeVarInt(@as(u32, @bitCast(self.data)));
        try stream.writeVarString(self.actorIdentifier);
        try stream.writeBool(self.isBabyMob);
        try stream.writeBool(self.isGlobal);
        try stream.writeInt64(self.uniqueActorId, .Little);
        return stream.getBuffer();
    }
};
