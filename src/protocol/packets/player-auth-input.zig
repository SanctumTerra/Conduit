const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const Vector2f = @import("../types/vector2f.zig").Vector2f;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const PlayerAuthInputData = @import("../types/player-auth-input-data.zig").PlayerAuthInputData;
const InputMode = @import("../enums/input-mode.zig").InputMode;
const PlayMode = @import("../enums/play-mode.zig").PlayMode;
const InteractionMode = @import("../enums/interaction-mode.zig").InteractionMode;
const InputData = @import("../enums/input-data.zig").InputData;
const PlayerBlockAction = @import("../types/player-block-action.zig").PlayerBlockAction;
const ItemUseTransaction = @import("../types/item-use-transaction.zig").ItemUseTransaction;
const ItemStackRequest = @import("../types/item-stack-request.zig").ItemStackRequest;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;

pub const PlayerAuthInputPacket = struct {
    rotation: Vector2f,
    position: Vector3f,
    motion: Vector2f,
    headYaw: f32,
    inputData: PlayerAuthInputData,
    inputMode: InputMode,
    playMode: PlayMode,
    interactionMode: InteractionMode,
    interactRotation: Vector2f,
    inputTick: u64,
    positionDelta: Vector3f,
    itemTransaction: ?ItemUseTransaction,
    blockActions: [MAX_BLOCK_ACTIONS]PlayerBlockAction,
    blockActionCount: u32,
    vehicleRotation: Vector2f,
    clientPredictedVehicle: i64,
    analogueMotion: Vector2f,
    cameraOrientation: Vector3f,
    rawMoveVector: Vector2f,

    const MAX_BLOCK_ACTIONS = 16;

    pub fn deserialize(stream: *BinaryStream) !PlayerAuthInputPacket {
        _ = try stream.readVarInt();

        const rotation = try Vector2f.read(stream);
        const position = try Vector3f.read(stream);
        const motion = try Vector2f.read(stream);
        const headYaw = try stream.readFloat32(.Little);
        const inputData = try PlayerAuthInputData.read(stream);
        const inputMode: InputMode = @enumFromInt(try stream.readVarInt());
        const playMode: PlayMode = @enumFromInt(try stream.readVarInt());
        const interactionMode: InteractionMode = @enumFromInt(try stream.readVarInt());
        const interactRotation = try Vector2f.read(stream);
        const inputTick: u64 = @intCast(try stream.readVarLong());
        const positionDelta = try Vector3f.read(stream);

        var itemTransaction: ?ItemUseTransaction = null;
        if (inputData.hasFlag(.PerformItemInteraction)) {
            itemTransaction = try ItemUseTransaction.read(stream);
        }

        if (inputData.hasFlag(.PerformItemStackRequest)) {
            try ItemStackRequest.skip(stream);
        }

        var blockActions: [MAX_BLOCK_ACTIONS]PlayerBlockAction = undefined;
        var blockActionCount: u32 = 0;
        if (inputData.hasFlag(.PerformBlockActions)) {
            const count: u32 = @intCast(try stream.readZigZag());
            const read_count = @min(count, MAX_BLOCK_ACTIONS);
            for (0..read_count) |i| {
                blockActions[i] = try PlayerBlockAction.read(stream);
            }
            for (read_count..count) |_| {
                _ = try PlayerBlockAction.read(stream);
            }
            blockActionCount = read_count;
        }

        var vehicleRotation = Vector2f.init(0, 0);
        var clientPredictedVehicle: i64 = 0;
        if (inputData.hasFlag(.IsInClientPredictedVehicle)) {
            vehicleRotation = try Vector2f.read(stream);
            clientPredictedVehicle = try stream.readZigZong();
        }

        const analogueMotion = try Vector2f.read(stream);
        const cameraOrientation = try Vector3f.read(stream);
        const rawMoveVector = try Vector2f.read(stream);

        return PlayerAuthInputPacket{
            .rotation = rotation,
            .position = position,
            .motion = motion,
            .headYaw = headYaw,
            .inputData = inputData,
            .inputMode = inputMode,
            .playMode = playMode,
            .interactionMode = interactionMode,
            .interactRotation = interactRotation,
            .inputTick = inputTick,
            .positionDelta = positionDelta,
            .itemTransaction = itemTransaction,
            .blockActions = blockActions,
            .blockActionCount = blockActionCount,
            .vehicleRotation = vehicleRotation,
            .clientPredictedVehicle = clientPredictedVehicle,
            .analogueMotion = analogueMotion,
            .cameraOrientation = cameraOrientation,
            .rawMoveVector = rawMoveVector,
        };
    }

    pub fn serialize(self: *PlayerAuthInputPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.PlayerAuthInput);

        try Vector2f.write(stream, self.rotation);
        try Vector3f.write(stream, self.position);
        try Vector2f.write(stream, self.motion);
        try stream.writeFloat32(self.headYaw, .Little);
        try PlayerAuthInputData.write(stream, self.inputData);
        try stream.writeVarInt(@intFromEnum(self.inputMode));
        try stream.writeVarInt(@intFromEnum(self.playMode));
        try stream.writeVarInt(@intFromEnum(self.interactionMode));
        try Vector2f.write(stream, self.interactRotation);
        try stream.writeVarLong(@intCast(self.inputTick));
        try Vector3f.write(stream, self.positionDelta);

        if (self.inputData.hasFlag(.PerformBlockActions)) {
            try stream.writeZigZag(@intCast(self.blockActionCount));
            for (0..self.blockActionCount) |i| {
                try PlayerBlockAction.write(stream, self.blockActions[i]);
            }
        }

        if (self.inputData.hasFlag(.IsInClientPredictedVehicle)) {
            try Vector2f.write(stream, self.vehicleRotation);
            try stream.writeZigZong(self.clientPredictedVehicle);
        }

        try Vector2f.write(stream, self.analogueMotion);
        try Vector3f.write(stream, self.cameraOrientation);
        try Vector2f.write(stream, self.rawMoveVector);

        return stream.getBuffer();
    }

    pub fn getBlockActions(self: *const PlayerAuthInputPacket) []const PlayerBlockAction {
        return self.blockActions[0..self.blockActionCount];
    }
};
