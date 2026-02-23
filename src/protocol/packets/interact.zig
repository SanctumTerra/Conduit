const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const InteractAction = @import("../enums/interact-action.zig").InteractAction;

pub const InteractPacket = struct {
    action: InteractAction,
    actor_runtime_id: u64,
    position: ?Vector3f = null,

    pub fn serialize(self: *const InteractPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.Interact);
        try stream.writeUint8(@intFromEnum(self.action));
        try stream.writeVarLong(@intCast(self.actor_runtime_id));
        if (self.action == .InteractUpdate) {
            try Vector3f.write(stream, self.position orelse Vector3f.init(0, 0, 0));
        }
        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream) !InteractPacket {
        _ = try stream.readVarInt();
        const action_raw = try stream.readUint8();
        const action: InteractAction = std.meta.intToEnum(InteractAction, action_raw) catch return error.UnknownInteractAction;
        const actor_runtime_id: u64 = @intCast(try stream.readVarLong());
        var position: ?Vector3f = null;
        if (action == .InteractUpdate) {
            position = try Vector3f.read(stream);
        }
        return InteractPacket{
            .action = action,
            .actor_runtime_id = actor_runtime_id,
            .position = position,
        };
    }
};
