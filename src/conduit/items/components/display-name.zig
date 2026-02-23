const std = @import("std");
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;
const StringTag = NBT.StringTag;
const Tag = NBT.Tag;
const ItemType = @import("../item-type.zig").ItemType;

pub const IDENTIFIER = "minecraft:display_name";

pub fn register(item_type: *ItemType, display_name: ?[]const u8) !void {
    var compound = CompoundTag.init(item_type.allocator, IDENTIFIER);
    const name = display_name orelse item_type.identifier;
    try compound.add(.{ .String = StringTag.init(name, "value") });
    try item_type.components.set(IDENTIFIER, .{ .Compound = compound });
}

pub fn getDisplayName(item_type: *const ItemType) ?[]const u8 {
    const compound = item_type.components.getCompound(IDENTIFIER) orelse return null;
    const tag = compound.get("value") orelse return null;
    if (tag != .String) return null;
    return tag.String.value;
}
