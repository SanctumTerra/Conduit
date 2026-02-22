const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const ItemStackRequest = struct {
    requestId: i32,

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
};

fn skipAction(stream: *BinaryStream) !void {
    const action_type = try stream.readUint8();
    switch (action_type) {
        0 => try skipTransferAction(stream),
        1 => try skipTransferAction(stream),
        2 => try skipTransferAction(stream),
        3 => try skipDropAction(stream),
        4 => try skipDestroyAction(stream),
        5 => try skipConsumeAction(stream),
        6 => try skipCreateAction(stream),
        7 => try skipLabTableCombineAction(),
        8 => try skipBeaconPaymentAction(stream),
        9 => try skipMineBlockAction(stream),
        10 => try skipCraftRecipeAction(stream),
        11 => try skipAutoCraftRecipeAction(stream),
        12 => try skipCraftCreativeAction(stream),
        13 => try skipCraftRecipeOptionalAction(stream),
        14 => try skipGrindstoneAction(stream),
        15 => try skipLoomAction(stream),
        16 => try skipDeprecatedCraftResultAction(stream),
        else => {},
    }
}

fn skipSlotInfo(stream: *BinaryStream) !void {
    _ = try stream.readUint8();
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

fn skipConsumeAction(stream: *BinaryStream) !void {
    _ = try stream.readUint8();
    try skipSlotInfo(stream);
}

fn skipCreateAction(stream: *BinaryStream) !void {
    _ = try stream.readUint8();
}

fn skipLabTableCombineAction() !void {}

fn skipBeaconPaymentAction(stream: *BinaryStream) !void {
    _ = try stream.readZigZag();
    _ = try stream.readZigZag();
}

fn skipMineBlockAction(stream: *BinaryStream) !void {
    _ = try stream.readZigZag();
    _ = try stream.readZigZag();
    _ = try stream.readZigZag();
}

fn skipCraftRecipeAction(stream: *BinaryStream) !void {
    _ = try stream.readVarInt();
    _ = try stream.readUint8();
}

fn skipAutoCraftRecipeAction(stream: *BinaryStream) !void {
    _ = try stream.readVarInt();
    _ = try stream.readUint8();
    const count = try stream.readVarInt();
    for (0..count) |_| {
        _ = try stream.readUint8();
        _ = try stream.readUint8();
        _ = try stream.readUint8();
        _ = try stream.readUint8();
    }
}

fn skipCraftCreativeAction(stream: *BinaryStream) !void {
    _ = try stream.readVarInt();
}

fn skipCraftRecipeOptionalAction(stream: *BinaryStream) !void {
    _ = try stream.readVarInt();
    _ = try stream.readInt32(.Little);
}

fn skipGrindstoneAction(stream: *BinaryStream) !void {
    _ = try stream.readVarInt();
    _ = try stream.readZigZag();
}

fn skipLoomAction(stream: *BinaryStream) !void {
    _ = try stream.readVarString();
}

fn skipDeprecatedCraftResultAction(stream: *BinaryStream) !void {
    const count = try stream.readVarInt();
    for (0..count) |_| {
        try skipItemDescriptorCount(stream);
    }
    _ = try stream.readUint8();
}

fn skipItemDescriptorCount(stream: *BinaryStream) !void {
    const descriptor_type = try stream.readUint8();
    switch (descriptor_type) {
        0 => {},
        1 => {
            _ = try stream.readInt16(.Little);
            _ = try stream.readInt16(.Little);
        },
        2 => {
            _ = try stream.readVarString();
            _ = try stream.readInt16(.Little);
        },
        3 => {
            _ = try stream.readVarString();
        },
        4 => {
            _ = try stream.readVarString();
        },
        5 => {
            _ = try stream.readVarString();
            _ = try stream.readUint8();
        },
        6 => {
            _ = try stream.readZigZag();
        },
        else => {},
    }
    _ = try stream.readZigZag();
}
