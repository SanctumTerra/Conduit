const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const BlockPosition = @import("block-position.zig").BlockPosition;
const Vector3f = @import("vector3f.zig").Vector3f;

pub const ItemUseTransaction = struct {
    legacyRequestId: i32,
    actionType: u32,
    triggerType: u32,
    blockPosition: BlockPosition,
    blockFace: i32,
    hotBarSlot: i32,
    position: Vector3f,
    clickedPosition: Vector3f,
    blockRuntimeId: u32,
    clientPrediction: u32,

    pub fn read(stream: *BinaryStream) !ItemUseTransaction {
        const legacyRequestId = try stream.readZigZag();

        if (legacyRequestId < -1 and (@as(u32, @bitCast(legacyRequestId)) & 1) == 0) {
            const slot_count = try stream.readVarInt();
            for (0..slot_count) |_| {
                _ = try stream.readUint8();
                const byte_count = try stream.readVarInt();
                for (0..byte_count) |_| {
                    _ = try stream.readUint8();
                }
            }
        }

        const action_count = try stream.readVarInt();
        for (0..action_count) |_| {
            try skipInventoryAction(stream);
        }

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
            .legacyRequestId = legacyRequestId,
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
};

fn skipInventoryAction(stream: *BinaryStream) !void {
    const source_type = try stream.readVarInt();
    switch (source_type) {
        0 => {
            _ = try stream.readZigZag();
        },
        1 => {},
        2 => {
            _ = try stream.readVarInt();
        },
        3 => {},
        4 => {
            _ = try stream.readVarInt();
        },
        else => {},
    }
    _ = try stream.readVarInt();
    try skipNetworkItemStackDescriptor(stream);
    try skipNetworkItemStackDescriptor(stream);
}

fn skipNetworkItemStackDescriptor(stream: *BinaryStream) !void {
    const id = try stream.readZigZag();
    if (id == 0) return;

    _ = try stream.readUint16(.Little);
    _ = try stream.readVarInt();

    const has_net_id = try stream.readBool();
    if (has_net_id) {
        _ = try stream.readZigZag();
    }

    _ = try stream.readZigZag();
    try skipItemInstanceUserData(stream);
}

fn skipItemInstance(stream: *BinaryStream) !void {
    const stack_net_id = try stream.readZigZag();
    _ = stack_net_id;
    try skipNetworkItemStackDescriptor(stream);
}

fn skipItemInstanceUserData(stream: *BinaryStream) !void {
    const marker = try stream.readInt16(.Little);
    if (marker == 0) return;

    if (marker == -1) {
        const nbt_version = try stream.readUint8();
        _ = nbt_version;
        try skipNbtCompound(stream);
    }

    const can_place_count = try stream.readInt32(.Little);
    for (0..@intCast(can_place_count)) |_| {
        try skipString16LE(stream);
    }

    const can_destroy_count = try stream.readInt32(.Little);
    for (0..@intCast(can_destroy_count)) |_| {
        try skipString16LE(stream);
    }

    if (marker == -1) {
        const blocking_tick = try stream.readInt64(.Little);
        _ = blocking_tick;
    }
}

fn skipString16LE(stream: *BinaryStream) !void {
    const len: u32 = @intCast(try stream.readInt16(.Little));
    for (0..len) |_| {
        _ = try stream.readUint8();
    }
}

const NbtError = error{ EndOfBuffer, OutOfMemory };

fn skipNbtCompound(stream: *BinaryStream) NbtError!void {
    while (true) {
        const tag_type = stream.readUint8() catch return;
        if (tag_type == 0) break;

        const name_len = stream.readUint16(.Little) catch return;
        for (0..name_len) |_| {
            _ = stream.readUint8() catch return;
        }

        skipNbtPayload(stream, tag_type);
    }
}

fn skipNbtPayload(stream: *BinaryStream, tag_type: u8) void {
    switch (tag_type) {
        1 => _ = stream.readUint8() catch return,
        2 => _ = stream.readInt16(.Little) catch return,
        3 => _ = stream.readInt32(.Little) catch return,
        4 => _ = stream.readInt64(.Little) catch return,
        5 => _ = stream.readFloat32(.Little) catch return,
        6 => {
            _ = stream.readInt64(.Little) catch return;
        },
        7 => {
            const len: u32 = @intCast(stream.readInt32(.Little) catch return);
            for (0..len) |_| {
                _ = stream.readUint8() catch return;
            }
        },
        8 => {
            const len = stream.readUint16(.Little) catch return;
            for (0..len) |_| {
                _ = stream.readUint8() catch return;
            }
        },
        9 => {
            const list_type = stream.readUint8() catch return;
            const count: u32 = @intCast(stream.readInt32(.Little) catch return);
            for (0..count) |_| {
                skipNbtPayload(stream, list_type);
            }
        },
        10 => skipNbtCompound(stream) catch return,
        11 => {
            const len: u32 = @intCast(stream.readInt32(.Little) catch return);
            for (0..len) |_| {
                _ = stream.readInt32(.Little) catch return;
            }
        },
        12 => {
            const len: u32 = @intCast(stream.readInt32(.Little) catch return);
            for (0..len) |_| {
                _ = stream.readInt64(.Little) catch return;
            }
        },
        else => {},
    }
}
