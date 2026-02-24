const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../enums/packet.zig").Packet;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;
const PlayerActionType = @import("../enums/player-action-type.zig").PlayerActionType;

pub const PlayerActionPacket = struct {
    runtimeEntityId: u64,
    action: PlayerActionType,
    blockPosition: BlockPosition,
    resultPosition: BlockPosition,
    face: i32,

    pub fn deserialize(stream: *BinaryStream) !PlayerActionPacket {
        _ = try stream.readVarInt();
        const runtimeEntityId: u64 = @intCast(try stream.readVarLong());
        const action: PlayerActionType = @enumFromInt(try stream.readZigZag());
        const blockPosition = try BlockPosition.read(stream);
        const resultPosition = try BlockPosition.read(stream);
        const face = try stream.readZigZag();

        return .{
            .runtimeEntityId = runtimeEntityId,
            .action = action,
            .blockPosition = blockPosition,
            .resultPosition = resultPosition,
            .face = face,
        };
    }

    pub fn serialize(self: *const PlayerActionPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.PlayerAction);
        try stream.writeVarLong(self.runtimeEntityId);
        try stream.writeZigZag(@intFromEnum(self.action));
        try BlockPosition.write(stream, self.blockPosition);
        try BlockPosition.write(stream, self.resultPosition);
        try stream.writeZigZag(self.face);
        return stream.getBuffer();
    }
};
