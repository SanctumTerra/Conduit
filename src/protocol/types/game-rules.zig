const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const GameRuleType = enum(i32) {
    Bool = 1,
    Int = 2,
    Float = 3,
};

pub const GameRuleValue = union(GameRuleType) {
    Bool: bool,
    Int: i32,
    Float: f32,
};

pub const GameRules = struct {
    editable: bool,
    name: []const u8,
    type: GameRuleType,
    value: GameRuleValue,

    pub fn init(editable: bool, name: []const u8, rule_type: GameRuleType, value: GameRuleValue) GameRules {
        return GameRules{
            .editable = editable,
            .name = name,
            .type = rule_type,
            .value = value,
        };
    }

    pub fn read(stream: *BinaryStream) ![]GameRules {
        const amount = try stream.readVarInt();
        const rules = try stream.allocator.alloc(GameRules, @intCast(amount));

        for (0..@intCast(amount)) |i| {
            const name = try stream.readVarString();
            const editable = try stream.readBool();
            const rule_type_raw = try stream.readVarInt();
            const rule_type: GameRuleType = @enumFromInt(rule_type_raw);

            const value: GameRuleValue = switch (rule_type) {
                .Bool => .{ .Bool = try stream.readBool() },
                .Int => .{ .Int = try stream.readZigZag() },
                .Float => .{ .Float = try stream.readFloat32(.Little) },
            };

            rules[i] = GameRules{
                .editable = editable,
                .name = name,
                .type = rule_type,
                .value = value,
            };
        }

        return rules;
    }

    pub fn write(stream: *BinaryStream, rules: []const GameRules) !void {
        try stream.writeVarInt(@intCast(rules.len));

        for (rules) |rule| {
            try stream.writeVarString(rule.name);
            try stream.writeBool(rule.editable);
            try stream.writeVarInt(@intCast(@intFromEnum(rule.type)));

            switch (rule.value) {
                .Bool => |val| try stream.writeBool(val),
                .Int => |val| try stream.writeZigZag(val),
                .Float => |val| try stream.writeFloat32(val, .Little),
            }
        }
    }

    pub fn deinit(self: *GameRules, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
