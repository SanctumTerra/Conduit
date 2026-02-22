const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const AttributeName = @import("../enums/attribute-name.zig").AttributeName;
const AttributeModifier = @import("./attribute-modifier.zig").AttributeModifier;

pub const Attribute = struct {
    min: f32,
    max: f32,
    current: f32,
    default_min: f32,
    default_max: f32,
    default: f32,
    name: AttributeName,
    modifiers: std.ArrayList(AttributeModifier),
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        min: f32,
        max: f32,
        current: f32,
        default_min: f32,
        default_max: f32,
        default: f32,
        name: AttributeName,
    ) Attribute {
        return .{
            .min = min,
            .max = max,
            .current = current,
            .default_min = default_min,
            .default_max = default_max,
            .default = default,
            .name = name,
            .modifiers = std.ArrayList(AttributeModifier){
                .items = &[_]AttributeModifier{},
                .capacity = 0,
            },
            .allocator = allocator,
        };
    }

    pub fn create(
        allocator: std.mem.Allocator,
        name: AttributeName,
        minimum_value: f32,
        maximum_value: f32,
        current: ?f32,
        default_value: ?f32,
    ) Attribute {
        const curr = current orelse maximum_value;
        const def = default_value orelse maximum_value;

        return init(
            allocator,
            minimum_value,
            maximum_value,
            curr,
            minimum_value,
            maximum_value,
            def,
            name,
        );
    }

    pub fn deinit(self: *Attribute) void {
        for (self.modifiers.items) |*modifier| {
            modifier.deinit(self.allocator);
        }
        self.modifiers.deinit(self.allocator);
    }

    pub fn readSingle(stream: *BinaryStream, allocator: std.mem.Allocator) !Attribute {
        const min = try stream.readFloat32(.little);
        const max = try stream.readFloat32(.little);
        const current = try stream.readFloat32(.little);
        const default_min = try stream.readFloat32(.little);
        const default_max = try stream.readFloat32(.little);
        const default = try stream.readFloat32(.little);

        const name_str = try stream.readString(allocator);
        defer allocator.free(name_str);

        const name = AttributeName.fromString(name_str) orelse return error.InvalidAttributeName;

        var attribute = init(allocator, min, max, current, default_min, default_max, default, name);

        const modifier_count = try stream.readVarInt();
        try attribute.modifiers.ensureTotalCapacity(@intCast(modifier_count));

        var i: usize = 0;
        while (i < modifier_count) : (i += 1) {
            const modifier = try AttributeModifier.read(stream, allocator);
            try attribute.modifiers.append(modifier);
        }

        return attribute;
    }

    pub fn read(stream: *BinaryStream, allocator: std.mem.Allocator) !std.ArrayList(Attribute) {
        var attributes = std.ArrayList(Attribute).init(allocator);
        errdefer {
            for (attributes.items) |*attr| {
                attr.deinit();
            }
            attributes.deinit();
        }

        const count = try stream.readVarInt();
        try attributes.ensureTotalCapacity(@intCast(count));

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const attribute = try readSingle(stream, allocator);
            try attributes.append(attribute);
        }

        return attributes;
    }

    pub fn writeSingle(self: Attribute, stream: *BinaryStream) !void {
        try stream.writeFloat32(self.min, .Little);
        try stream.writeFloat32(self.max, .Little);
        try stream.writeFloat32(self.current, .Little);
        try stream.writeFloat32(self.default_min, .Little);
        try stream.writeFloat32(self.default_max, .Little);
        try stream.writeFloat32(self.default, .Little);
        try stream.writeVarString(self.name.toString());

        try stream.writeVarInt(@intCast(self.modifiers.items.len));
        for (self.modifiers.items) |modifier| {
            try modifier.write(stream);
        }
    }

    pub fn write(attributes: []const Attribute, stream: *BinaryStream) !void {
        try stream.writeVarInt(@intCast(attributes.len));
        for (attributes) |attribute| {
            try attribute.writeSingle(stream);
        }
    }

    fn truncate(value: f32) f32 {
        return @floor(value * 10000.0) / 10000.0;
    }

    pub fn setCurrent(self: *Attribute, value: f32) void {
        self.current = truncate(value);
    }

    pub fn setMin(self: *Attribute, value: f32) void {
        self.min = truncate(value);
    }

    pub fn setMax(self: *Attribute, value: f32) void {
        self.max = truncate(value);
    }

    pub fn setDefault(self: *Attribute, value: f32) void {
        self.default = truncate(value);
    }

    pub fn reset(self: *Attribute) void {
        self.current = self.default;
    }
};
