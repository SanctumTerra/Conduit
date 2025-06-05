const BinaryStream = @import("BinaryStream").BinaryStream;
const std = @import("std");
const CAllocator = @import("CAllocator");
const Packets = @import("../Packets.zig").Packets;

pub const ItemData = struct {
    pub fn write(self: *const ItemData, stream: *BinaryStream) void {
        _ = self;
        _ = stream;
        // TODO: Implement
    }
};

pub const ItemRegistryPacket = struct {
    definitions: std.ArrayList(ItemData),

    pub fn init() ItemRegistryPacket {
        return .{ .definitions = std.ArrayList(ItemData).init(CAllocator.get()) };
    }

    pub fn deinit(self: *ItemRegistryPacket) void {
        self.definitions.deinit();
    }

    pub fn serialize(self: *ItemRegistryPacket) []const u8 {
        var stream = BinaryStream.init(CAllocator.get(), &[_]u8{}, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.ItemRegistry, .Big);
        stream.writeVarInt(@as(u32, @intCast(self.definitions.items.len)), .Big);
        if (self.definitions.items.len > 0) {
            for (self.definitions.items) |definition| {
                definition.write(&stream);
            }
        }
        return stream.toOwnedSlice() catch @panic("Failed to allocate memory for ItemRegistryPacket");
    }
};
