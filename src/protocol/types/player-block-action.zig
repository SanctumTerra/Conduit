const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const PlayerActionType = @import("../enums/player-action-type.zig").PlayerActionType;
const BlockPosition = @import("block-position.zig").BlockPosition;

pub const PlayerBlockAction = struct {
    action: PlayerActionType,
    blockPos: BlockPosition,
    face: i32,

    fn readBlockPos(stream: *BinaryStream) !BlockPosition {
        const x = try stream.readZigZag();
        const y = try stream.readZigZag();
        const z = try stream.readZigZag();
        return BlockPosition{ .x = x, .y = y, .z = z };
    }

    fn writeBlockPos(stream: *BinaryStream, value: BlockPosition) !void {
        try stream.writeZigZag(value.x);
        try stream.writeZigZag(value.y);
        try stream.writeZigZag(value.z);
    }

    pub fn read(stream: *BinaryStream) !PlayerBlockAction {
        const action: PlayerActionType = @enumFromInt(try stream.readZigZag());
        var blockPos = BlockPosition.init(0, 0, 0);
        var face: i32 = 0;

        if (action.hasBlockPos()) {
            blockPos = try readBlockPos(stream);
            face = try stream.readZigZag();
        }

        return .{
            .action = action,
            .blockPos = blockPos,
            .face = face,
        };
    }

    pub fn write(stream: *BinaryStream, value: PlayerBlockAction) !void {
        try stream.writeZigZag(@intFromEnum(value.action));
        if (value.action.hasBlockPos()) {
            try writeBlockPos(stream, value.blockPos);
            try stream.writeZigZag(value.face);
        }
    }
};
