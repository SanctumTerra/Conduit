const BinaryStream = @import("BinaryStream").BinaryStream;
const AbilitySet = @import("ability-set.zig").AbilitySet;

pub const AbilityLayer = struct {
    layer_type: u16,
    abilities: []AbilitySet,
    fly_speed: f32,
    vertical_fly_speed: f32,
    walk_speed: f32,

    pub fn write(self: *const AbilityLayer, stream: *BinaryStream) !void {
        try stream.writeUint16(self.layer_type, .Little);

        var available: u32 = 0;
        var enabled: u32 = 0;
        for (self.abilities) |ability_set| {
            const bit_pos: u5 = @intFromEnum(ability_set.ability);
            available |= @as(u32, 1) << bit_pos;
            if (ability_set.value) {
                enabled |= @as(u32, 1) << bit_pos;
            }
        }

        try stream.writeUint32(available, .Little);
        try stream.writeUint32(enabled, .Little);
        try stream.writeFloat32(self.fly_speed, .Little);
        try stream.writeFloat32(self.vertical_fly_speed, .Little);
        try stream.writeFloat32(self.walk_speed, .Little);
    }
};
