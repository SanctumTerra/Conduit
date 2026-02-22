const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Attribute = @import("../types/attribute.zig").Attribute;

pub const UpdateAttributesPacket = struct {
    runtime_actor_id: i64,
    attributes: std.ArrayList(Attribute),
    tick: u64,

    pub fn init(_: std.mem.Allocator, runtime_actor_id: i64, tick: u64) UpdateAttributesPacket {
        return .{
            .runtime_actor_id = runtime_actor_id,
            .attributes = std.ArrayList(Attribute){
                .items = &[_]Attribute{},
                .capacity = 0,
            },
            .tick = tick,
        };
    }

    pub fn deinit(self: *UpdateAttributesPacket, allocator: std.mem.Allocator) void {
        for (self.attributes.items) |*attr| {
            attr.deinit();
        }
        self.attributes.deinit(allocator);
    }

    pub fn serialize(self: *const UpdateAttributesPacket, stream: *BinaryStream) ![]const u8 {
        const Packet = @import("../enums/packet.zig").Packet;
        try stream.writeVarInt(Packet.UpdateAttributes);

        try stream.writeVarLong(@bitCast(self.runtime_actor_id));
        try Attribute.write(self.attributes.items, stream);
        try stream.writeVarLong(@intCast(self.tick));

        return stream.getBuffer();
    }

    pub fn deserialize(stream: *BinaryStream, allocator: std.mem.Allocator) !UpdateAttributesPacket {
        const runtime_actor_id = try stream.readVarLong();
        const attributes = try Attribute.read(stream, allocator);
        const tick = try stream.readVarLong();

        return UpdateAttributesPacket{
            .runtime_actor_id = runtime_actor_id,
            .attributes = attributes,
            .tick = @intCast(tick),
        };
    }
};
