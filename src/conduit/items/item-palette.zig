const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Data = @import("protocol").Data;
const NBT = @import("nbt");
const ItemType = @import("./item-type.zig").ItemType;

pub fn loadItemTypes(allocator: std.mem.Allocator) !usize {
    const types_parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        Data.item_types_json,
        .{},
    );
    defer types_parsed.deinit();

    const metadata_parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        Data.item_metadata_json,
        .{},
    );
    defer metadata_parsed.deinit();

    const types_array = if (types_parsed.value == .array) types_parsed.value.array.items else return error.InvalidJsonFormat;
    const metadata_array = if (metadata_parsed.value == .array) metadata_parsed.value.array.items else return error.InvalidJsonFormat;

    var metadata_map = std.StringHashMap(MetadataEntry).init(allocator);
    defer {
        var iter = metadata_map.valueIterator();
        while (iter.next()) |entry| {
            if (!entry.consumed) {
                var props = entry.properties;
                props.deinit(allocator);
            }
        }
        metadata_map.deinit();
    }

    for (metadata_array) |entry| {
        if (entry != .object) continue;
        const obj = entry.object;
        const identifier = if (obj.get("identifier")) |id| if (id == .string) id.string else continue else continue;
        const network_id = if (obj.get("networkId")) |n| if (n == .integer) @as(i32, @intCast(n.integer)) else continue else continue;
        const is_component_based = if (obj.get("isComponentBased")) |b| if (b == .bool) b.bool else false else false;
        const version = if (obj.get("itemVersion")) |v| if (v == .integer) @as(i32, @intCast(v.integer)) else 0 else 0;
        const properties_b64 = if (obj.get("properties")) |p| if (p == .string) p.string else "" else "";
        const properties = try parseNbtFromBase64(allocator, properties_b64);
        try metadata_map.put(identifier, .{
            .network_id = network_id,
            .is_component_based = is_component_based,
            .version = version,
            .properties = properties,
        });
    }

    var loaded: usize = 0;

    for (types_array) |entry| {
        if (entry != .object) continue;
        const obj = entry.object;

        const identifier = if (obj.get("identifier")) |id| if (id == .string) id.string else continue else continue;
        const stackable = if (obj.get("stackable")) |s| if (s == .bool) s.bool else true else true;
        const max_amount: u16 = if (obj.get("maxAmount")) |m| if (m == .integer) @intCast(m.integer) else 64 else 64;

        const meta_ptr = metadata_map.getPtr(identifier) orelse continue;
        meta_ptr.consumed = true;
        const meta = meta_ptr.*;

        const json_tags = if (obj.get("tags")) |t| if (t == .array) t.array.items else &[_]std.json.Value{} else &[_]std.json.Value{};

        var tags = try allocator.alloc([]const u8, json_tags.len);
        var tag_count: usize = 0;
        for (json_tags) |tag_val| {
            if (tag_val == .string) {
                tags[tag_count] = try allocator.dupe(u8, tag_val.string);
                tag_count += 1;
            }
        }
        tags = try allocator.realloc(tags, tag_count);

        const duped_id = try allocator.dupe(u8, identifier);

        const item_type = try ItemType.init(
            allocator,
            duped_id,
            meta.network_id,
            max_amount,
            stackable,
            tags,
            meta.is_component_based,
            meta.version,
            meta.properties,
        );
        try item_type.register();
        loaded += 1;
    }

    return loaded;
}

pub fn getItemRegistry(allocator: std.mem.Allocator) ![]const ItemRegistryEntry {
    const all = ItemType.getAll();
    var entries = try allocator.alloc(ItemRegistryEntry, all.count());
    var i: usize = 0;
    var iter = all.valueIterator();
    while (iter.next()) |item_type| {
        entries[i] = .{
            .identifier = item_type.*.identifier,
            .network_id = @intCast(item_type.*.network_id),
            .is_component_based = item_type.*.is_component_based,
            .version = item_type.*.version,
            .properties = &item_type.*.properties,
        };
        i += 1;
    }
    return entries;
}

pub fn initRegistry(allocator: std.mem.Allocator) !void {
    try ItemType.initRegistry(allocator);
}

pub fn deinitRegistry() void {
    ItemType.deinitRegistry();
}

const Protocol = @import("protocol");
const ItemRegistryEntry = Protocol.ItemRegistryEntry;

const MetadataEntry = struct {
    network_id: i32,
    is_component_based: bool,
    version: i32,
    properties: NBT.Tag,
    consumed: bool = false,
};

fn parseNbtFromBase64(allocator: std.mem.Allocator, input: []const u8) !NBT.Tag {
    if (input.len == 0) return NBT.Tag{ .Compound = NBT.CompoundTag.init(allocator, null) };
    const decoder = std.base64.standard.decoderWithIgnore("");
    const size = try decoder.calcSizeUpperBound(input.len);
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    const decoded_len = try decoder.decode(buf, input);
    var stream = BinaryStream.init(allocator, buf[0..decoded_len], null);
    return NBT.Tag.read(&stream, allocator, .{ .name = true, .tag_type = true, .varint = false });
}
