const std = @import("std");
const NBT = @import("nbt");

pub const ItemType = struct {
    identifier: []const u8,
    network_id: i32,
    max_stack_size: u16,
    stackable: bool,
    tags: []const []const u8,
    is_component_based: bool,
    version: i32,
    properties: NBT.Tag,

    allocator: std.mem.Allocator,

    var types: std.StringHashMap(*ItemType) = undefined;
    var network_map: std.AutoHashMap(i32, *ItemType) = undefined;
    var types_initialized = false;

    pub fn initRegistry(allocator: std.mem.Allocator) !void {
        if (!types_initialized) {
            types = std.StringHashMap(*ItemType).init(allocator);
            network_map = std.AutoHashMap(i32, *ItemType).init(allocator);
            types_initialized = true;
        }
    }

    pub fn deinitRegistry() void {
        if (types_initialized) {
            var iter = types.valueIterator();
            while (iter.next()) |item_type| {
                item_type.*.deinit();
            }
            types.deinit();
            network_map.deinit();
            types_initialized = false;
        }
    }

    pub fn init(
        allocator: std.mem.Allocator,
        identifier: []const u8,
        network_id: i32,
        max_stack_size: u16,
        stackable: bool,
        tags: []const []const u8,
        is_component_based: bool,
        version: i32,
        properties: NBT.Tag,
    ) !*ItemType {
        const item = try allocator.create(ItemType);
        item.* = .{
            .identifier = identifier,
            .network_id = network_id,
            .max_stack_size = max_stack_size,
            .stackable = stackable,
            .tags = tags,
            .is_component_based = is_component_based,
            .version = version,
            .properties = properties,
            .allocator = allocator,
        };
        return item;
    }

    pub fn deinit(self: *ItemType) void {
        self.allocator.free(self.identifier);
        for (self.tags) |tag| {
            self.allocator.free(tag);
        }
        self.allocator.free(self.tags);
        self.properties.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn register(self: *ItemType) !void {
        try types.put(self.identifier, self);
        try network_map.put(self.network_id, self);
    }

    pub fn get(identifier: []const u8) ?*ItemType {
        return types.get(identifier);
    }

    pub fn getByNetworkId(network_id: i32) ?*ItemType {
        return network_map.get(network_id);
    }

    pub fn getAll() std.StringHashMap(*ItemType) {
        return types;
    }

    pub fn hasTag(self: *const ItemType, tag: []const u8) bool {
        for (self.tags) |t| {
            if (std.mem.eql(u8, t, tag)) return true;
        }
        return false;
    }

    pub fn isTool(self: *const ItemType) bool {
        return self.hasTag("minecraft:is_tool");
    }

    pub fn isSword(self: *const ItemType) bool {
        return self.hasTag("minecraft:is_sword");
    }

    pub fn isPickaxe(self: *const ItemType) bool {
        return self.hasTag("minecraft:is_pickaxe");
    }

    pub fn isAxe(self: *const ItemType) bool {
        return self.hasTag("minecraft:is_axe");
    }

    pub fn isShovel(self: *const ItemType) bool {
        return self.hasTag("minecraft:is_shovel");
    }

    pub fn isHoe(self: *const ItemType) bool {
        return self.hasTag("minecraft:is_hoe");
    }

    pub const AIR = "minecraft:air";
};
