const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const Experiment = struct {
    name: []const u8,
    enabled: bool,
};

pub const Experiments = struct {
    name: []const u8,
    enabled: bool,

    pub fn init(name: []const u8, enabled: bool) Experiments {
        return .{
            .name = name,
            .enabled = enabled,
        };
    }

    pub fn deinit(self: *Experiments, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) ![]Experiments {
        const amount = stream.readZigZag(.Little);

        var experiments = try std.ArrayList(Experiments).initCapacity(allocator, @intCast(amount));
        errdefer {
            for (experiments.items) |*experiment| {
                experiment.deinit(allocator);
            }
            experiments.deinit();
        }

        var i: usize = 0;
        while (i < amount) : (i += 1) {
            const name = stream.readVarString();
            const name_copy = try allocator.dupe(u8, name);
            errdefer allocator.free(name_copy);

            const enabled = stream.readBool();

            const experiment = Experiments{
                .name = name_copy,
                .enabled = enabled,
            };

            try experiments.append(experiment);
        }

        return experiments.toOwnedSlice();
    }

    pub fn write(self: Experiments, stream: *BinaryStream) void {
        stream.writeVarString(self.name);

        stream.writeBool(self.enabled);
    }

    pub fn writeList(experiments: []const Experiments, stream: *BinaryStream) void {
        stream.writeInt32(@intCast(experiments.len), .Little);
        std.debug.print("Experiments: {}\n", .{experiments.len});
        if (experiments.len > 0) {
            for (experiments) |experiment| {
                experiment.write(stream);
            }
        }
    }

    pub fn toExperiment(self: Experiments, allocator: std.mem.Allocator) !Experiment {
        return Experiment{
            .name = try allocator.dupe(u8, self.name),
            .enabled = self.enabled,
        };
    }
};
