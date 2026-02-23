const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const Vector3f = @import("../types/vector3f.zig").Vector3f;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;
const TransactionTypes = @import("../types/inventory-transaction-data.zig");

pub const TransactionType = @import("../enums/transaction-type.zig").TransactionType;
pub const TransactionData = TransactionTypes.TransactionData;
pub const UseItemTransactionData = TransactionTypes.UseItemTransactionData;
pub const UseItemOnEntityTransactionData = TransactionTypes.UseItemOnEntityTransactionData;
pub const ReleaseItemTransactionData = TransactionTypes.ReleaseItemTransactionData;
pub const InventoryAction = TransactionTypes.InventoryAction;
pub const LegacySetItemSlot = TransactionTypes.LegacySetItemSlot;

pub const InventoryTransactionPacket = struct {
    legacyRequestId: i32,
    transactionType: TransactionType,
    actionCount: u32,
    transactionData: TransactionData,

    pub fn deserialize(stream: *BinaryStream) !InventoryTransactionPacket {
        _ = try stream.readVarInt();

        const legacyRequestId = try stream.readZigZag();

        if (legacyRequestId != 0) {
            const slot_count = try stream.readVarInt();
            for (0..slot_count) |_| {
                _ = try stream.readUint8();
                const byte_count = try stream.readVarInt();
                for (0..byte_count) |_| {
                    _ = try stream.readUint8();
                }
            }
        }

        const transactionTypeRaw = try stream.readVarInt();
        const transactionType: TransactionType = std.meta.intToEnum(TransactionType, transactionTypeRaw) catch return error.InvalidTransactionType;

        const actionCount = try stream.readVarInt();
        for (0..actionCount) |_| {
            try skipInventoryAction(stream);
        }

        const transactionData: TransactionData = switch (transactionType) {
            .Normal => .{ .normal = {} },
            .Mismatch => .{ .mismatch = {} },
            .UseItem => .{ .useItem = try readUseItem(stream) },
            .UseItemOnEntity => .{ .useItemOnEntity = try readUseItemOnEntity(stream) },
            .ReleaseItem => .{ .releaseItem = try readReleaseItem(stream) },
        };

        return .{
            .legacyRequestId = legacyRequestId,
            .transactionType = transactionType,
            .actionCount = actionCount,
            .transactionData = transactionData,
        };
    }
};

fn readUseItem(stream: *BinaryStream) !UseItemTransactionData {
    const actionType = try stream.readVarInt();
    const triggerType = try stream.readVarInt();
    const blockPosition = try BlockPosition.read(stream);
    const blockFace = try stream.readZigZag();
    const hotBarSlot = try stream.readZigZag();
    try skipItemInstance(stream);
    const position = try Vector3f.read(stream);
    const clickedPosition = try Vector3f.read(stream);
    const blockRuntimeId = try stream.readVarInt();
    const clientPrediction = try stream.readVarInt();

    return .{
        .actionType = actionType,
        .triggerType = triggerType,
        .blockPosition = blockPosition,
        .blockFace = blockFace,
        .hotBarSlot = hotBarSlot,
        .position = position,
        .clickedPosition = clickedPosition,
        .blockRuntimeId = blockRuntimeId,
        .clientPrediction = clientPrediction,
    };
}

fn readUseItemOnEntity(stream: *BinaryStream) !UseItemOnEntityTransactionData {
    const targetEntityRuntimeId = try stream.readVarLong();
    const actionType = try stream.readVarInt();
    const hotBarSlot = try stream.readZigZag();
    try skipItemInstance(stream);
    const position = try Vector3f.read(stream);
    const clickedPosition = try Vector3f.read(stream);

    return .{
        .targetEntityRuntimeId = targetEntityRuntimeId,
        .actionType = actionType,
        .hotBarSlot = hotBarSlot,
        .position = position,
        .clickedPosition = clickedPosition,
    };
}

fn readReleaseItem(stream: *BinaryStream) !ReleaseItemTransactionData {
    const actionType = try stream.readVarInt();
    const hotBarSlot = try stream.readZigZag();
    try skipItemInstance(stream);
    const headPosition = try Vector3f.read(stream);

    return .{
        .actionType = actionType,
        .hotBarSlot = hotBarSlot,
        .headPosition = headPosition,
    };
}

fn skipInventoryAction(stream: *BinaryStream) !void {
    const source_type = try stream.readVarInt();
    switch (source_type) {
        0, 99999 => _ = try stream.readZigZag(),
        2 => _ = try stream.readVarInt(),
        else => {},
    }
    _ = try stream.readVarInt();
    try skipItemInstance(stream);
    try skipItemInstance(stream);
}

fn skipItemInstance(stream: *BinaryStream) !void {
    const network_id = try stream.readZigZag();
    if (network_id == 0) return;

    _ = try stream.readUint16(.Little);
    _ = try stream.readVarInt();

    if (try stream.readBool()) {
        _ = try stream.readZigZag();
    }

    _ = try stream.readZigZag();

    const extra_len = try stream.readVarInt();
    for (0..extra_len) |_| {
        _ = try stream.readUint8();
    }
}
