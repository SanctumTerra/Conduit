const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const FullContainerName = @import("full-container-name.zig").FullContainerName;
pub const StackRequestActionType = @import("../enums/stack-request-action-type.zig").StackRequestActionType;

pub const StackRequestSlotInfo = struct {
    container: FullContainerName,
    slot: u8,
    stackNetworkId: i32,
};

pub const TransferAction = struct {
    count: u8,
    source: StackRequestSlotInfo,
    destination: StackRequestSlotInfo,
};

pub const DropAction = struct {
    count: u8,
    source: StackRequestSlotInfo,
    randomly: bool,
};

pub const DestroyAction = struct {
    count: u8,
    source: StackRequestSlotInfo,
};

pub const CreateAction = struct {
    resultsSlot: u8,
};

pub const BeaconPaymentAction = struct {
    primaryEffect: i32,
    secondaryEffect: i32,
};

pub const MineBlockAction = struct {
    hotbarSlot: i32,
    predictedDurability: i32,
    stackNetworkId: i32,
};

pub const CraftRecipeAction = struct {
    recipeNetworkId: u32,
    numberOfCrafts: u8,
};

pub const CraftCreativeAction = struct {
    creativeItemNetworkId: u32,
    numberOfCrafts: u8,
};

pub const CraftRecipeOptionalAction = struct {
    recipeNetworkId: u32,
    filterStringIndex: i32,
};

pub const CraftGrindstoneAction = struct {
    recipeNetworkId: u32,
    numberOfCrafts: u8,
    cost: i32,
};

pub const CraftLoomAction = struct {
    pattern: []const u8,
    timesCrafted: u8,
};

pub const StackRequestAction = union(enum) {
    take: TransferAction,
    place: TransferAction,
    swap: struct { source: StackRequestSlotInfo, destination: StackRequestSlotInfo },
    drop: DropAction,
    destroy: DestroyAction,
    consume: DestroyAction,
    create: CreateAction,
    placeInContainer: TransferAction,
    takeOutContainer: TransferAction,
    labTableCombine: void,
    beaconPayment: BeaconPaymentAction,
    mineBlock: MineBlockAction,
    craftRecipe: CraftRecipeAction,
    craftRecipeAuto: CraftRecipeAction,
    craftCreative: CraftCreativeAction,
    craftRecipeOptional: CraftRecipeOptionalAction,
    craftGrindstone: CraftGrindstoneAction,
    craftLoom: CraftLoomAction,
    craftNonImplementedDeprecated: void,
    craftResultsDeprecated: void,
    unknown: void,
};

pub const ItemStackRequest = struct {
    requestId: i32,
    actions: []StackRequestAction,
    filterStrings: [][]const u8,
    filterCause: i32,

    pub fn skip(stream: *BinaryStream) !void {
        _ = try stream.readZigZag();
        const action_count = try stream.readVarInt();
        for (0..action_count) |_| {
            try skipAction(stream);
        }
        const filter_count = try stream.readVarInt();
        for (0..filter_count) |_| {
            _ = try stream.readVarString();
        }
        _ = try stream.readInt32(.Little);
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !ItemStackRequest {
        const requestId = try stream.readZigZag();
        const action_count = try stream.readVarInt();
        var actions = try allocator.alloc(StackRequestAction, action_count);
        for (0..action_count) |i| {
            actions[i] = try readAction(stream);
        }
        const filter_count = try stream.readVarInt();
        var filterStrings = try allocator.alloc([]const u8, filter_count);
        for (0..filter_count) |i| {
            filterStrings[i] = try stream.readVarString();
        }
        const filterCause = try stream.readInt32(.Little);
        return .{
            .requestId = requestId,
            .actions = actions,
            .filterStrings = filterStrings,
            .filterCause = filterCause,
        };
    }
};

fn readSlotInfo(stream: *BinaryStream) !StackRequestSlotInfo {
    const container = try FullContainerName.read(stream);
    const slot = try stream.readUint8();
    const stackNetworkId = try stream.readZigZag();
    return .{ .container = container, .slot = slot, .stackNetworkId = stackNetworkId };
}

fn readTransferAction(stream: *BinaryStream) !TransferAction {
    const count = try stream.readUint8();
    const source = try readSlotInfo(stream);
    const destination = try readSlotInfo(stream);
    return .{ .count = count, .source = source, .destination = destination };
}

fn readAction(stream: *BinaryStream) !StackRequestAction {
    const action_type: StackRequestActionType = @enumFromInt(try stream.readUint8());
    return switch (action_type) {
        .Take => .{ .take = try readTransferAction(stream) },
        .Place => .{ .place = try readTransferAction(stream) },
        .Swap => {
            const source = try readSlotInfo(stream);
            const destination = try readSlotInfo(stream);
            return .{ .swap = .{ .source = source, .destination = destination } };
        },
        .Drop => {
            const count = try stream.readUint8();
            const source = try readSlotInfo(stream);
            const randomly = try stream.readBool();
            return .{ .drop = .{ .count = count, .source = source, .randomly = randomly } };
        },
        .Destroy => {
            const count = try stream.readUint8();
            const source = try readSlotInfo(stream);
            return .{ .destroy = .{ .count = count, .source = source } };
        },
        .Consume => {
            const count = try stream.readUint8();
            const source = try readSlotInfo(stream);
            return .{ .consume = .{ .count = count, .source = source } };
        },
        .Create => .{ .create = .{ .resultsSlot = try stream.readUint8() } },
        .PlaceInContainer => .{ .placeInContainer = try readTransferAction(stream) },
        .TakeOutContainer => .{ .takeOutContainer = try readTransferAction(stream) },
        .LabTableCombine => .{ .labTableCombine = {} },
        .BeaconPayment => .{ .beaconPayment = .{
            .primaryEffect = try stream.readZigZag(),
            .secondaryEffect = try stream.readZigZag(),
        } },
        .MineBlock => .{ .mineBlock = .{
            .hotbarSlot = try stream.readZigZag(),
            .predictedDurability = try stream.readZigZag(),
            .stackNetworkId = try stream.readZigZag(),
        } },
        .CraftRecipe => .{ .craftRecipe = .{
            .recipeNetworkId = try stream.readVarInt(),
            .numberOfCrafts = try stream.readUint8(),
        } },
        .CraftRecipeAuto => blk: {
            const rid = try stream.readVarInt();
            const nc = try stream.readUint8();
            _ = try stream.readUint8();
            const ic = try stream.readVarInt();
            for (0..ic) |_| try skipItemDescriptorCount(stream);
            break :blk .{ .craftRecipeAuto = .{ .recipeNetworkId = rid, .numberOfCrafts = nc } };
        },
        .CraftCreative => .{ .craftCreative = .{
            .creativeItemNetworkId = try stream.readVarInt(),
            .numberOfCrafts = try stream.readUint8(),
        } },
        .CraftRecipeOptional => .{ .craftRecipeOptional = .{
            .recipeNetworkId = try stream.readVarInt(),
            .filterStringIndex = try stream.readInt32(.Little),
        } },
        .CraftGrindstone => .{ .craftGrindstone = .{
            .recipeNetworkId = try stream.readVarInt(),
            .numberOfCrafts = try stream.readUint8(),
            .cost = try stream.readZigZag(),
        } },
        .CraftLoom => .{ .craftLoom = .{
            .pattern = try stream.readVarString(),
            .timesCrafted = try stream.readUint8(),
        } },
        .CraftNonImplementedDeprecated => .{ .craftNonImplementedDeprecated = {} },
        .CraftResultsDeprecated => blk: {
            const c = try stream.readVarInt();
            for (0..c) |_| try skipItemStack(stream);
            _ = try stream.readUint8();
            break :blk .{ .craftResultsDeprecated = {} };
        },
        _ => .{ .unknown = {} },
    };
}

fn skipAction(stream: *BinaryStream) !void {
    const action_type = try stream.readUint8();
    switch (action_type) {
        0, 1, 7, 8 => try skipTransferAction(stream),
        2 => {
            try skipSlotInfo(stream);
            try skipSlotInfo(stream);
        },
        3 => try skipDropAction(stream),
        4, 5 => try skipDestroyAction(stream),
        6 => _ = try stream.readUint8(),
        9 => {},
        10 => {
            _ = try stream.readZigZag();
            _ = try stream.readZigZag();
        },
        11 => {
            _ = try stream.readZigZag();
            _ = try stream.readZigZag();
            _ = try stream.readZigZag();
        },
        12 => {
            _ = try stream.readVarInt();
            _ = try stream.readUint8();
        },
        13 => {
            _ = try stream.readVarInt();
            _ = try stream.readUint8();
            _ = try stream.readUint8();
            const c = try stream.readVarInt();
            for (0..c) |_| try skipItemDescriptorCount(stream);
        },
        14 => {
            _ = try stream.readVarInt();
            _ = try stream.readUint8();
        },
        15 => {
            _ = try stream.readVarInt();
            _ = try stream.readInt32(.Little);
        },
        16 => {
            _ = try stream.readVarInt();
            _ = try stream.readUint8();
            _ = try stream.readZigZag();
        },
        17 => {
            _ = try stream.readVarString();
            _ = try stream.readUint8();
        },
        18 => {},
        19 => {
            const c = try stream.readVarInt();
            for (0..c) |_| try skipItemStack(stream);
            _ = try stream.readUint8();
        },
        else => {},
    }
}

fn skipSlotInfo(stream: *BinaryStream) !void {
    _ = try FullContainerName.read(stream);
    _ = try stream.readUint8();
    _ = try stream.readZigZag();
}

fn skipTransferAction(stream: *BinaryStream) !void {
    _ = try stream.readUint8();
    try skipSlotInfo(stream);
    try skipSlotInfo(stream);
}

fn skipDropAction(stream: *BinaryStream) !void {
    _ = try stream.readUint8();
    try skipSlotInfo(stream);
    _ = try stream.readBool();
}

fn skipDestroyAction(stream: *BinaryStream) !void {
    _ = try stream.readUint8();
    try skipSlotInfo(stream);
}

fn skipItemDescriptorCount(stream: *BinaryStream) !void {
    const dt = try stream.readUint8();
    switch (dt) {
        0 => {},
        1 => {
            _ = try stream.readInt16(.Little);
            _ = try stream.readInt16(.Little);
        },
        2 => {
            _ = try stream.readVarString();
            _ = try stream.readInt16(.Little);
        },
        3, 4 => _ = try stream.readVarString(),
        5 => {
            _ = try stream.readVarString();
            _ = try stream.readUint8();
        },
        6 => _ = try stream.readZigZag(),
        else => {},
    }
    _ = try stream.readZigZag();
}

fn skipItemStack(stream: *BinaryStream) !void {
    const nid = try stream.readZigZag();
    if (nid == 0) return;
    _ = try stream.readUint16(.Little);
    _ = try stream.readVarInt();
    _ = try stream.readZigZag();
    const el = try stream.readVarInt();
    for (0..el) |_| _ = try stream.readUint8();
}
