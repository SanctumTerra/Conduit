const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ActorDataType = @import("../enums/actor-data-type.zig").ActorDataType;
const BlockPosition = @import("./block-position.zig").BlockPosition;
const Vector3f = @import("./vector3f.zig").Vector3f;

pub const DataItem = struct {
    id: u32,
    type: ActorDataType,
    value: DataValue,

    pub const DataValue = union(ActorDataType) {
        Byte: i8,
        Short: i16,
        Int: i32,
        Float: f32,
        String: []const u8,
        CompoundTag: []const u8,
        BlockPosition: BlockPosition,
        Long: i64,
        Vector3f: Vector3f,
    };

    pub fn init(id: u32, data_type: ActorDataType, value: DataValue) DataItem {
        return .{
            .id = id,
            .type = data_type,
            .value = value,
        };
    }

    pub fn initShort(id: u32, value: i16) DataItem {
        return init(id, .Short, .{ .Short = value });
    }

    pub fn initInt(id: u32, value: i32) DataItem {
        return init(id, .Int, .{ .Int = value });
    }

    pub fn initFloat(id: u32, value: f32) DataItem {
        return init(id, .Float, .{ .Float = value });
    }

    pub fn initByte(id: u32, value: i8) DataItem {
        return init(id, .Byte, .{ .Byte = value });
    }

    pub fn write(self: DataItem, stream: *BinaryStream) !void {
        try stream.writeVarInt(@intCast(self.id));
        try stream.writeVarInt(@intFromEnum(self.type));

        switch (self.value) {
            .Byte => |v| try stream.writeInt8(v),
            .Short => |v| try stream.writeInt16(v, .Little),
            .Int => |v| try stream.writeZigZag(v),
            .Float => |v| try stream.writeFloat32(v, .Little),
            .String => |v| try stream.writeVarString(v),
            .CompoundTag => |v| {
                try stream.write(v);
            },
            .BlockPosition => |v| try BlockPosition.write(stream, v),
            .Long => |v| try stream.writeZigZong(v),
            .Vector3f => |v| try Vector3f.write(stream, v),
        }
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !DataItem {
        const id: u32 = @intCast(try stream.readVarInt());
        const type_val: u32 = @intCast(try stream.readVarInt());
        const data_type: ActorDataType = @enumFromInt(@as(u8, @intCast(type_val)));

        const value: DataValue = switch (data_type) {
            .Byte => .{ .Byte = try stream.readInt8() },
            .Short => .{ .Short = try stream.readInt16(.Little) },
            .Int => .{ .Int = try stream.readZigZag() },
            .Float => .{ .Float = try stream.readFloat32(.Little) },
            .String => .{ .String = try stream.readVarString(allocator) },
            .CompoundTag => {
                const len = try stream.readVarInt();
                const data = try allocator.alloc(u8, @intCast(len));
                _ = try stream.read(data);
                return .{ .CompoundTag = data };
            },
            .BlockPosition => .{ .BlockPosition = try BlockPosition.read(stream) },
            .Long => .{ .Long = try stream.readZigZong() },
            .Vector3f => .{ .Vector3f = try Vector3f.read(stream) },
        };

        return DataItem{
            .id = id,
            .type = data_type,
            .value = value,
        };
    }

    pub fn deinit(self: *DataItem, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .String => |v| allocator.free(v),
            .CompoundTag => |v| allocator.free(v),
            else => {},
        }
    }
};
