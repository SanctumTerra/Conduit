const Vector3f = @import("vector3f.zig").Vector3f;
const BlockPosition = @import("block-position.zig").BlockPosition;

pub const LegacySetItemSlot = struct {
    containerId: u8,
    slots: []const u8,
};

pub const InventoryAction = struct {
    sourceType: u32,
    windowId: i32,
    sourceFlags: u32,
    inventorySlot: u32,
};

pub const UseItemTransactionData = struct {
    actionType: u32,
    triggerType: u32,
    blockPosition: BlockPosition,
    blockFace: i32,
    hotBarSlot: i32,
    position: Vector3f,
    clickedPosition: Vector3f,
    blockRuntimeId: u32,
    clientPrediction: u32,
};

pub const UseItemOnEntityTransactionData = struct {
    targetEntityRuntimeId: u64,
    actionType: u32,
    hotBarSlot: i32,
    position: Vector3f,
    clickedPosition: Vector3f,
};

pub const ReleaseItemTransactionData = struct {
    actionType: u32,
    hotBarSlot: i32,
    headPosition: Vector3f,
};

pub const TransactionData = union(enum) {
    normal: void,
    mismatch: void,
    useItem: UseItemTransactionData,
    useItemOnEntity: UseItemOnEntityTransactionData,
    releaseItem: ReleaseItemTransactionData,
};
