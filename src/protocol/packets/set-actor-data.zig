const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const DataItem = @import("../types/data-item.zig").DataItem;
const PropertySyncData = @import("../types/property-sync-data.zig").PropertySyncData;

pub const SetActorDataPacket = struct {
    runtime_entity_id: i64,
    data: []DataItem,
    properties: PropertySyncData,
    tick: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, runtime_entity_id: i64, tick: u64, data: []DataItem) SetActorDataPacket {
        return .{
            .runtime_entity_id = runtime_entity_id,
            .data = data,
            .properties = PropertySyncData.init(allocator),
            .tick = tick,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SetActorDataPacket) void {
        for (self.data) |*item| {
            var mutable_item = item.*;
            mutable_item.deinit(self.allocator);
        }
        self.allocator.free(self.data);
        self.properties.deinit();
    }

    pub fn serialize(self: *const SetActorDataPacket, stream: *BinaryStream) ![]const u8 {
        const Packet = @import("../enums/packet.zig").Packet;
        try stream.writeVarInt(Packet.SetActorData);

        try stream.writeVarLong(@bitCast(self.runtime_entity_id));

        try stream.writeVarInt(@intCast(self.data.len));
        for (self.data) |item| {
            try item.write(stream);
        }

        try self.properties.write(stream);

        try stream.writeVarLong(self.tick);

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream, allocator: std.mem.Allocator) !SetActorDataPacket {
        const runtime_entity_id: i64 = @bitCast(try stream.readVarLong());

        const count = try stream.readVarInt();
        const data = try allocator.alloc(DataItem, @intCast(count));
        errdefer allocator.free(data);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            data[i] = try DataItem.read(stream, allocator);
        }

        const properties = try PropertySyncData.read(stream, allocator);
        const tick = try stream.readVarLong();

        return SetActorDataPacket{
            .runtime_entity_id = runtime_entity_id,
            .data = data,
            .properties = properties,
            .tick = tick,
            .allocator = allocator,
        };
    }
};
