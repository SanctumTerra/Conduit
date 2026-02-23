const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const DataItem = @import("../types/data-item.zig").DataItem;
const PropertySyncData = @import("../types/property-sync-data.zig").PropertySyncData;

pub const AddEntityPacket = struct {
    uniqueEntityId: i64,
    runtimeEntityId: u64,
    entityType: []const u8,
    position: Vector3f,
    velocity: Vector3f = Vector3f.init(0, 0, 0),
    pitch: f32 = 0,
    yaw: f32 = 0,
    headYaw: f32 = 0,
    bodyYaw: f32 = 0,
    entityMetadata: []const DataItem = &[_]DataItem{},
    entityProperties: PropertySyncData,

    pub fn serialize(self: *const AddEntityPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.AddEntity);
        try stream.writeZigZong(self.uniqueEntityId);
        try stream.writeVarLong(self.runtimeEntityId);
        try stream.writeVarString(self.entityType);
        try Vector3f.write(stream, self.position);
        try Vector3f.write(stream, self.velocity);
        try stream.writeFloat32(self.pitch, .Little);
        try stream.writeFloat32(self.yaw, .Little);
        try stream.writeFloat32(self.headYaw, .Little);
        try stream.writeFloat32(self.bodyYaw, .Little);

        // attributes (empty)
        try stream.writeVarInt(0);

        // entity metadata
        try stream.writeVarInt(@intCast(self.entityMetadata.len));
        for (self.entityMetadata) |item| {
            try item.write(stream);
        }

        try self.entityProperties.write(stream);

        // entity links (empty)
        try stream.writeVarInt(0);

        return stream.getBuffer();
    }
};
