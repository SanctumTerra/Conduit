const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const GameRuleType = enum(u32) {
    Boolean = 0,
    Integer = 1,
    Float = 2,
    String = 3,
};

pub const Gamerule = struct {
    name: []const u8,
    value: []const u8,
};

pub const GameRules = struct {
    editable: bool,
    name: []const u8,
    type: GameRuleType,
    value: union {
        boolean: bool,
        integer: i32,
        float: f32,
        string: []const u8,
    },

    pub fn init(editable: bool, name: []const u8, rule_type: GameRuleType, value: anytype) GameRules {
        var rule = GameRules{
            .editable = editable,
            .name = name,
            .type = rule_type,
            .value = undefined,
        };

        switch (rule_type) {
            .Boolean => rule.value = .{ .boolean = value },
            .Integer => rule.value = .{ .integer = value },
            .Float => rule.value = .{ .float = value },
            .String => rule.value = .{ .string = value },
        }

        return rule;
    }

    pub fn deinit(self: *GameRules, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.type == .String) {
            allocator.free(self.value.string);
        }
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) ![]GameRules {
        const amount = stream.readVarInt(.Big);

        var rules = try std.ArrayList(GameRules).initCapacity(allocator, amount);
        errdefer {
            for (rules.items) |*rule| {
                rule.deinit(allocator);
            }
            rules.deinit();
        }

        var i: usize = 0;
        while (i < amount) : (i += 1) {
            const name = stream.readVarString();
            const name_copy = try allocator.dupe(u8, name);
            errdefer allocator.free(name_copy);

            const editable = stream.readBool();

            const rule_type_int = stream.readVarInt(.Big);
            const rule_type = std.meta.intToEnum(GameRuleType, rule_type_int) catch @panic("Unknown GameRuleType");

            var rule: GameRules = undefined;
            rule.editable = editable;
            rule.name = name_copy;
            rule.type = rule_type;

            switch (rule_type) {
                .Boolean => {
                    rule.value = .{ .boolean = stream.readBool() };
                },
                .Integer => {
                    rule.value = .{ .integer = stream.readZigZag() };
                },
                .Float => {
                    rule.value = .{ .float = stream.readFloat32(.Little) };
                },
                .String => {
                    const str_value = stream.readVarString();
                    const str_copy = try allocator.dupe(u8, str_value);
                    errdefer allocator.free(str_copy);
                    rule.value = .{ .string = str_copy };
                },
            }

            try rules.append(rule);
        }

        return rules.toOwnedSlice();
    }

    pub fn write(self: GameRules, stream: *BinaryStream) void {
        stream.writeVarString(self.name);

        stream.writeBool(self.editable);

        stream.writeVarInt(@intFromEnum(self.type), .Big);

        switch (self.type) {
            .Boolean => {
                stream.writeBool(self.value.boolean);
            },
            .Integer => {
                stream.writeZigZag(self.value.integer);
            },
            .Float => {
                stream.writeFloat32(self.value.float, .Little);
            },
            .String => {
                stream.writeVarString(self.value.string);
            },
        }
    }

    pub fn writeList(rules: []const GameRules, stream: *BinaryStream) void {
        stream.writeVarInt(@intCast(rules.len), .Big);

        for (rules) |rule| {
            rule.write(stream);
        }
    }

    pub fn toStringValue(self: GameRules, allocator: std.mem.Allocator) ![]const u8 {
        switch (self.type) {
            .Boolean => {
                return if (self.value.boolean)
                    try allocator.dupe(u8, "true")
                else
                    try allocator.dupe(u8, "false");
            },
            .Integer => {
                return try std.fmt.allocPrint(allocator, "{d}", .{self.value.integer});
            },
            .Float => {
                return try std.fmt.allocPrint(allocator, "{d}", .{self.value.float});
            },
            .String => {
                return try allocator.dupe(u8, self.value.string);
            },
        }
    }

    pub fn toGamerule(self: GameRules, allocator: std.mem.Allocator) !Gamerule {
        const value = try self.toStringValue(allocator);
        return Gamerule{
            .name = try allocator.dupe(u8, self.name),
            .value = value,
        };
    }
};
