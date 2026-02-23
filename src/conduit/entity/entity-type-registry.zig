const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const NBT = Protocol.NBT;
const EntityType = @import("./entity-type.zig").EntityType;

var registry: ?*EntityTypeRegistry = null;

pub const EntityTypeRegistry = struct {
    allocator: std.mem.Allocator,
    types: std.StringHashMap(EntityType),
    serialized_packet: []const u8,

    pub fn get(identifier: []const u8) ?*const EntityType {
        const reg = registry orelse return null;
        return reg.types.getPtr(identifier);
    }

    pub fn getSerializedPacket() ?[]const u8 {
        const reg = registry orelse return null;
        return reg.serialized_packet;
    }

    pub fn deinit() void {
        if (registry) |reg| {
            var it = reg.types.iterator();
            while (it.next()) |entry| {
                const et = entry.value_ptr.*;
                for (et.components) |comp| {
                    reg.allocator.free(comp);
                }
                if (et.components.len > 0) reg.allocator.free(et.components);
                reg.allocator.free(et.identifier);
            }
            reg.types.deinit();
            reg.allocator.free(reg.serialized_packet);
            reg.allocator.destroy(reg);
            registry = null;
        }
    }
};

pub fn initRegistry(allocator: std.mem.Allocator) !usize {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        Protocol.Data.entity_types_json,
        .{},
    );
    defer parsed.deinit();

    const arr = if (parsed.value == .array) parsed.value.array.items else return error.InvalidJsonFormat;

    var types = std.StringHashMap(EntityType).init(allocator);

    var network_id: i32 = 1;
    for (arr) |item| {
        if (item != .object) continue;
        const obj = item.object;
        const identifier = if (obj.get("identifier")) |id| if (id == .string) id.string else continue else continue;

        const id_dupe = try allocator.dupe(u8, identifier);

        const components: []const []const u8 = blk: {
            const comp_val = obj.get("components") orelse break :blk &[_][]const u8{};
            if (comp_val != .array) break :blk &[_][]const u8{};
            const comp_arr = comp_val.array.items;
            if (comp_arr.len == 0) break :blk &[_][]const u8{};
            const comps = try allocator.alloc([]const u8, comp_arr.len);
            var count: usize = 0;
            for (comp_arr) |c| {
                if (c == .string) {
                    comps[count] = try allocator.dupe(u8, c.string);
                    count += 1;
                }
            }
            if (count == 0) {
                allocator.free(comps);
                break :blk &[_][]const u8{};
            }
            break :blk try allocator.realloc(comps, count);
        };

        try types.put(id_dupe, EntityType.init(id_dupe, network_id, components, &.{}));
        network_id += 1;
    }

    const serialized_packet = try serializePacket(allocator, &types);

    const reg = try allocator.create(EntityTypeRegistry);
    reg.* = .{
        .allocator = allocator,
        .types = types,
        .serialized_packet = serialized_packet,
    };
    registry = reg;

    return types.count();
}

fn serializePacket(allocator: std.mem.Allocator, types: *std.StringHashMap(EntityType)) ![]const u8 {
    const count = types.count() + 1;
    const entries = try allocator.alloc(NBT.Tag, count);

    var player_entry = NBT.CompoundTag.init(allocator, null);
    const player_id_name = try allocator.dupe(u8, "id");
    const player_id_value = try allocator.dupe(u8, "minecraft:player");
    try player_entry.value.put(allocator, "id", NBT.Tag{ .String = NBT.StringTag.init(player_id_value, player_id_name) });
    entries[0] = NBT.Tag{ .Compound = player_entry };

    var idx: usize = 1;
    var it = types.iterator();
    while (it.next()) |entry| {
        var compound = NBT.CompoundTag.init(allocator, null);
        const id_name = try allocator.dupe(u8, "id");
        const id_value = try allocator.dupe(u8, entry.key_ptr.*);
        try compound.value.put(allocator, "id", NBT.Tag{ .String = NBT.StringTag.init(id_value, id_name) });
        entries[idx] = NBT.Tag{ .Compound = compound };
        idx += 1;
    }

    var data = NBT.CompoundTag.init(allocator, null);
    const list_name = try allocator.dupe(u8, "idlist");
    const idlist = NBT.ListTag.init(entries, list_name);
    try data.value.put(allocator, "idlist", NBT.Tag{ .List = idlist });

    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    try stream.writeVarInt(Protocol.Packet.AvailableActorIdentifiers);
    try NBT.CompoundTag.write(&stream, &data, .{ .varint = true });

    data.deinit(allocator);

    const buf = stream.getBuffer();
    const serialized = try allocator.alloc(u8, buf.len);
    @memcpy(serialized, buf);
    return serialized;
}
