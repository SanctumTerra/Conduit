pub const RequestChunkRadius = struct {
    pub const Self = @This();
    radius: i32,
    maxRadius: u8,

    pub fn init(radius: i32, maxRadius: u8) Self {
        return Self{
            .radius = radius,
            .maxRadius = maxRadius,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn deserialize(data: []const u8) !Self {
        var stream = BinaryStream.init(CAllocator.get(), data, 0);
        defer stream.deinit();
        stream.writeVarInt(Packets.RequestChunkRadius);
        const radius = stream.readZigZag();
        const maxRadius = stream.readUint8();
        return Self.init(radius, maxRadius);
    }
};

const BinaryStream = @import("BinaryStream").BinaryStream;
const CAllocator = @import("CAllocator");
const Packets = @import("../enums/Packets.zig").Packets;
