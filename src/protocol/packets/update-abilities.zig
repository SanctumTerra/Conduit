const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const AbilityLayer = @import("../types/ability-layer.zig").AbilityLayer;

pub const UpdateAbilitiesPacket = struct {
    entity_unique_id: i64,
    permission_level: u8,
    command_permission_level: u8,
    layers: []AbilityLayer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, entity_unique_id: i64, permission_level: u8, command_permission_level: u8, layers: []AbilityLayer) UpdateAbilitiesPacket {
        return .{
            .entity_unique_id = entity_unique_id,
            .permission_level = permission_level,
            .command_permission_level = command_permission_level,
            .layers = layers,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UpdateAbilitiesPacket) void {
        for (self.layers) |*layer| {
            self.allocator.free(layer.abilities);
        }
        self.allocator.free(self.layers);
    }

    pub fn serialize(self: *const UpdateAbilitiesPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.UpdateAbilities);
        try stream.writeInt64(self.entity_unique_id, .Little);
        try stream.writeUint8(self.permission_level);
        try stream.writeUint8(self.command_permission_level);
        try stream.writeUint8(@intCast(self.layers.len));

        for (self.layers) |layer| {
            try layer.write(stream);
        }

        return stream.getBuffer();
    }
};
