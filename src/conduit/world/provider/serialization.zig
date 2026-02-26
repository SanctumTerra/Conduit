const std = @import("std");
const NBT = @import("nbt");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const CompoundTag = NBT.CompoundTag;
const ListTag = NBT.ListTag;
const Tag = NBT.Tag;
const FloatTag = NBT.FloatTag;
const LongTag = NBT.LongTag;
const StringTag = NBT.StringTag;
const ByteTag = NBT.ByteTag;
const ShortTag = NBT.ShortTag;
const IntTag = NBT.IntTag;
const ReadWriteOptions = NBT.ReadWriteOptions;

const ItemStack = @import("../../items/item-stack.zig").ItemStack;
const ItemType = @import("../../items/item-type.zig").ItemType;
const Container = @import("../../container/container.zig").Container;
const Entity = @import("../../entity/entity.zig").Entity;
const Player = @import("../../player/player.zig").Player;
const InventoryTrait = @import("../../entity/traits/inventory.zig").InventoryTrait;
const HealthTrait = @import("../../entity/traits/health.zig").HealthTrait;

pub fn serializeItemStack(allocator: std.mem.Allocator, item: *const ItemStack) !CompoundTag {
    var tag = CompoundTag.init(allocator, null);
    try tag.set("Name", .{ .String = StringTag.init(try allocator.dupe(u8, item.item_type.identifier), null) });
    try tag.set("Count", .{ .Byte = ByteTag.init(@intCast(@min(item.stackSize, 127)), null) });
    try tag.set("Damage", .{ .Short = ShortTag.init(@intCast(item.metadata), null) });
    if (item.nbt) |nbt| {
        if (nbt.get("tag")) |tag_entry| {
            switch (tag_entry) {
                .Compound => |c| {
                    var nbt_copy = try copyCompound(allocator, &c);
                    if (nbt_copy.name) |old_name| allocator.free(old_name);
                    nbt_copy.name = try allocator.dupe(u8, "tag");
                    try tag.add(.{ .Compound = nbt_copy });
                },
                else => {},
            }
        }
    }
    return tag;
}

pub fn deserializeItemStack(allocator: std.mem.Allocator, tag: *const CompoundTag) ?ItemStack {
    const name_tag = tag.get("Name") orelse return null;
    const name = switch (name_tag) {
        .String => |s| s.value,
        else => return null,
    };
    if (std.mem.eql(u8, name, "minecraft:air") or std.mem.eql(u8, name, "")) return null;

    const item_type = ItemType.get(name) orelse return null;

    const count: u16 = blk: {
        const count_tag = tag.get("Count") orelse break :blk 1;
        break :blk switch (count_tag) {
            .Byte => |b| @intCast(@as(u8, @bitCast(b.value))),
            else => 1,
        };
    };

    const metadata: u32 = blk: {
        const dmg_tag = tag.get("Damage") orelse break :blk 0;
        break :blk switch (dmg_tag) {
            .Short => |s| @intCast(@as(u16, @bitCast(s.value))),
            else => 0,
        };
    };

    const nbt_data: ?CompoundTag = blk: {
        const extra = tag.get("tag") orelse break :blk null;
        switch (extra) {
            .Compound => |c| {
                var tag_copy = copyCompound(allocator, &c) catch break :blk null;
                if (tag_copy.name) |old_name| allocator.free(old_name);
                tag_copy.name = allocator.dupe(u8, "tag") catch {
                    tag_copy.deinit(allocator);
                    break :blk null;
                };
                var root = CompoundTag.init(allocator, null);
                root.add(.{ .Compound = tag_copy }) catch {
                    tag_copy.deinit(allocator);
                    root.deinit(allocator);
                    break :blk null;
                };
                break :blk root;
            },
            else => break :blk null,
        }
    };

    return ItemStack.init(allocator, item_type, .{
        .stackSize = count,
        .metadata = metadata,
        .nbt = nbt_data,
    });
}

pub fn serializeContainer(allocator: std.mem.Allocator, container: *const Container) !ListTag {
    var items = std.ArrayList(Tag){ .items = &.{}, .capacity = 0 };
    for (container.storage, 0..) |slot, i| {
        if (slot) |*item| {
            var item_tag = try serializeItemStack(allocator, item);
            try item_tag.set("Slot", .{ .Byte = ByteTag.init(@intCast(i), null) });
            try items.append(allocator, .{ .Compound = item_tag });
        }
    }
    return ListTag.init(try items.toOwnedSlice(allocator), null);
}

pub fn deserializeContainer(allocator: std.mem.Allocator, container: *Container, list: *const ListTag) void {
    for (list.value) |*entry| {
        switch (entry.*) {
            .Compound => |*compound| {
                const slot_tag = compound.get("Slot") orelse continue;
                const slot: u32 = switch (slot_tag) {
                    .Byte => |b| @intCast(@as(u8, @bitCast(b.value))),
                    else => continue,
                };
                if (slot >= container.getSize()) continue;
                if (deserializeItemStack(allocator, compound)) |item| {
                    if (container.storage[slot]) |*old| old.deinit();
                    container.storage[slot] = item;
                }
            },
            else => {},
        }
    }
}

pub fn serializeEntity(allocator: std.mem.Allocator, entity: *Entity) !CompoundTag {
    var tag = CompoundTag.init(allocator, null);
    try tag.set("identifier", .{ .String = StringTag.init(try allocator.dupe(u8, entity.entity_type.identifier), null) });
    try tag.set("UniqueID", .{ .Long = LongTag.init(entity.unique_id, null) });

    var pos_items = try allocator.alloc(Tag, 3);
    pos_items[0] = .{ .Float = FloatTag.init(entity.position.x, null) };
    pos_items[1] = .{ .Float = FloatTag.init(entity.position.y, null) };
    pos_items[2] = .{ .Float = FloatTag.init(entity.position.z, null) };
    try tag.set("Pos", .{ .List = ListTag.init(pos_items, null) });

    var rot_items = try allocator.alloc(Tag, 2);
    rot_items[0] = .{ .Float = FloatTag.init(entity.rotation.x, null) };
    rot_items[1] = .{ .Float = FloatTag.init(entity.rotation.y, null) };
    try tag.set("Rotation", .{ .List = ListTag.init(rot_items, null) });

    var motion_items = try allocator.alloc(Tag, 3);
    motion_items[0] = .{ .Float = FloatTag.init(entity.motion.x, null) };
    motion_items[1] = .{ .Float = FloatTag.init(entity.motion.y, null) };
    motion_items[2] = .{ .Float = FloatTag.init(entity.motion.z, null) };
    try tag.set("Motion", .{ .List = ListTag.init(motion_items, null) });

    entity.fireEvent(.Serialize, .{&tag});

    return tag;
}

pub fn deserializeEntity(_: std.mem.Allocator, entity: *Entity, tag: *const CompoundTag) void {
    if (tag.get("UniqueID")) |uid| {
        switch (uid) {
            .Long => |l| entity.unique_id = l.value,
            else => {},
        }
    }

    if (tag.get("Pos")) |pos| {
        switch (pos) {
            .List => |list| {
                if (list.value.len >= 3) {
                    entity.position = Protocol.Vector3f.init(
                        getFloat(&list.value[0]),
                        getFloat(&list.value[1]),
                        getFloat(&list.value[2]),
                    );
                }
            },
            else => {},
        }
    }

    if (tag.get("Rotation")) |rot| {
        switch (rot) {
            .List => |list| {
                if (list.value.len >= 2) {
                    entity.rotation = Protocol.Vector2f.init(
                        getFloat(&list.value[0]),
                        getFloat(&list.value[1]),
                    );
                }
            },
            else => {},
        }
    }

    if (tag.get("Motion")) |motion| {
        switch (motion) {
            .List => |list| {
                if (list.value.len >= 3) {
                    entity.motion = Protocol.Vector3f.init(
                        getFloat(&list.value[0]),
                        getFloat(&list.value[1]),
                        getFloat(&list.value[2]),
                    );
                }
            },
            else => {},
        }
    }

    entity.fireEvent(.Deserialize, .{tag});
}

pub fn serializePlayer(allocator: std.mem.Allocator, player: *Player) !CompoundTag {
    var tag = try serializeEntity(allocator, &player.entity);

    if (player.entity.getTraitState(InventoryTrait)) |inv_state| {
        const inv_list = try serializeContainer(allocator, &inv_state.container.base);
        try tag.set("Inventory", .{ .List = inv_list });
        try tag.set("SelectedInventorySlot", .{ .Int = IntTag.init(@intCast(inv_state.selected_slot), null) });
    }

    if (player.entity.getTraitState(HealthTrait)) |health_state| {
        try tag.set("Health", .{ .Float = FloatTag.init(health_state.current, null) });
        try tag.set("MaxHealth", .{ .Float = FloatTag.init(health_state.max, null) });
    }

    try tag.set("DimensionId", .{ .Int = IntTag.init(0, null) });

    return tag;
}

pub fn deserializePlayer(allocator: std.mem.Allocator, player: *Player, tag: *const CompoundTag) void {
    deserializeEntity(allocator, &player.entity, tag);

    if (player.entity.getTraitState(InventoryTrait)) |inv_state| {
        if (tag.get("Inventory")) |inv| {
            switch (inv) {
                .List => |list| {
                    deserializeContainer(allocator, &inv_state.container.base, &list);
                },
                else => {},
            }
        }
        if (tag.get("SelectedInventorySlot")) |slot| {
            switch (slot) {
                .Int => |i| inv_state.selected_slot = @intCast(@as(u32, @bitCast(i.value)) % 36),
                else => {},
            }
        }
    }

    if (player.entity.getTraitState(HealthTrait)) |health_state| {
        if (tag.get("Health")) |h| {
            switch (h) {
                .Float => |f| health_state.current = f.value,
                else => {},
            }
        }
        if (tag.get("MaxHealth")) |h| {
            switch (h) {
                .Float => |f| health_state.max = f.value,
                else => {},
            }
        }
    }
}

pub fn encodeNbt(allocator: std.mem.Allocator, tag: *const CompoundTag) ![]const u8 {
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();
    try CompoundTag.write(&stream, tag, ReadWriteOptions.default);
    return try allocator.dupe(u8, stream.getBuffer());
}

pub fn decodeNbt(allocator: std.mem.Allocator, data: []const u8) !CompoundTag {
    var stream = BinaryStream.init(allocator, data, null);
    defer stream.deinit();
    return try CompoundTag.read(&stream, allocator, ReadWriteOptions.default);
}

fn getFloat(tag: *const Tag) f32 {
    return switch (tag.*) {
        .Float => |f| f.value,
        else => 0,
    };
}

fn copyCompound(allocator: std.mem.Allocator, src: *const CompoundTag) !CompoundTag {
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();
    try CompoundTag.write(&stream, src, ReadWriteOptions.default);
    var read_stream = BinaryStream.init(allocator, stream.getBuffer(), null);
    defer read_stream.deinit();
    return try CompoundTag.read(&read_stream, allocator, ReadWriteOptions.default);
}
