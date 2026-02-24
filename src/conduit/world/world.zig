const std = @import("std");
const Protocol = @import("protocol");
const Conduit = @import("../conduit.zig").Conduit;
const Dimension = @import("./dimension/dimension.zig").Dimension;
const WorldProvider = @import("./provider/world-provider.zig").WorldProvider;
const InternalProvider = @import("./provider/internal-provider.zig").InternalProvider;
const ThreadedGenerator = @import("./generator/threaded-generator.zig").ThreadedGenerator;

pub const World = struct {
    conduit: *Conduit,
    allocator: std.mem.Allocator,
    identifier: []const u8,
    dimensions: std.StringHashMap(*Dimension),
    provider: WorldProvider,

    pub fn init(
        conduit: *Conduit,
        allocator: std.mem.Allocator,
        identifier: []const u8,
        provider: ?WorldProvider,
    ) !World {
        const prov = provider orelse blk: {
            const internal = try InternalProvider.init(allocator);
            break :blk internal.asProvider();
        };

        return World{
            .conduit = conduit,
            .allocator = allocator,
            .identifier = identifier,
            .dimensions = std.StringHashMap(*Dimension).init(allocator),
            .provider = prov,
        };
    }

    pub fn createDimension(
        self: *World,
        identifier: []const u8,
        dimension_type: Protocol.DimensionType,
        generator: ?*ThreadedGenerator,
    ) !*Dimension {
        if (self.dimensions.get(identifier)) |existing| return existing;

        const dim = try self.allocator.create(Dimension);
        dim.* = Dimension.init(self, self.allocator, identifier, dimension_type, generator);
        try dim.loadSpawnChunks();
        try self.dimensions.put(identifier, dim);
        return dim;
    }

    pub fn getDimension(self: *World, identifier: []const u8) ?*Dimension {
        return self.dimensions.get(identifier);
    }

    pub fn deinit(self: *World) void {
        var iter = self.dimensions.valueIterator();
        while (iter.next()) |dim| {
            dim.*.deinit();
            self.allocator.destroy(dim.*);
        }
        self.dimensions.deinit();
        self.provider.deinit();
    }
};
