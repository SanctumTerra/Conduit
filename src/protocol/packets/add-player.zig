const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Uuid = @import("../types/uuid.zig").Uuid;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const Rotation = @import("../types/rotation.zig").Rotation;
const DataItem = @import("../types/data-item.zig").DataItem;
const PropertySyncData = @import("../types/property-sync-data.zig").PropertySyncData;
const AbilityLayer = @import("../types/ability-layer.zig").AbilityLayer;

pub const AddPlayerPacket = struct {
    uuid: []const u8,
    username: []const u8,
    entityRuntimeId: i64,
    platformChatId: []const u8 = "",
    position: Vector3f,
    velocity: Vector3f = Vector3f.init(0, 0, 0),
    rotation: Rotation = Rotation.init(0, 0, 0),
    gameType: i32 = 1,
    entityMetadata: []const DataItem = &[_]DataItem{},
    entityProperties: PropertySyncData,
    abilityEntityUniqueId: i64 = 0,
    permissionLevel: u8 = 0,
    commandPermissionLevel: u8 = 0,
    abilityLayers: []const AbilityLayer = &[_]AbilityLayer{},
    deviceId: []const u8 = "",
    buildPlatform: i32 = 0,

    pub fn serialize(self: *const AddPlayerPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.AddActor);
        try Uuid.write(stream, self.uuid);
        try stream.writeVarString(self.username);
        try stream.writeVarLong(@bitCast(self.entityRuntimeId));
        try stream.writeVarString(self.platformChatId);
        try Vector3f.write(stream, self.position);
        try Vector3f.write(stream, self.velocity);
        try Rotation.write(stream, self.rotation);
        try stream.writeZigZag(0);
        try stream.writeZigZag(self.gameType);

        try stream.writeVarInt(@intCast(self.entityMetadata.len));
        for (self.entityMetadata) |item| {
            try item.write(stream);
        }

        try self.entityProperties.write(stream);

        try stream.writeInt64(self.abilityEntityUniqueId, .Little);
        try stream.writeUint8(self.permissionLevel);
        try stream.writeUint8(self.commandPermissionLevel);
        try stream.writeUint8(@intCast(self.abilityLayers.len));
        for (self.abilityLayers) |layer| {
            try layer.write(stream);
        }

        try stream.writeVarInt(0);
        try stream.writeVarString(self.deviceId);
        try stream.writeInt32(self.buildPlatform, .Little);

        return stream.getBuffer();
    }
};
