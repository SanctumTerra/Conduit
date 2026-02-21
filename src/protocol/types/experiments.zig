const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const Experiments = struct {
    name: []const u8,
    enabled: bool,

    pub fn init(name: []const u8, enabled: bool) Experiments {
        return Experiments{
            .name = name,
            .enabled = enabled,
        };
    }

    pub fn read(stream: *BinaryStream) ![]Experiments {
        const amount = try stream.readInt32(.Little);
        const experiments = try stream.allocator.alloc(Experiments, @intCast(amount));

        for (0..@intCast(amount)) |i| {
            const name = try stream.readVarString();
            const enabled = try stream.readBool();

            experiments[i] = Experiments{
                .name = name,
                .enabled = enabled,
            };
        }

        return experiments;
    }

    pub fn write(stream: *BinaryStream, experiments: []const Experiments) !void {
        try stream.writeInt32(@intCast(experiments.len), .Little);

        for (experiments) |experiment| {
            try stream.writeVarString(experiment.name);
            try stream.writeBool(experiment.enabled);
        }
    }

    pub fn deinit(self: *Experiments, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
