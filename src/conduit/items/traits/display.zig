const std = @import("std");
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;
const StringTag = NBT.StringTag;
const ListTag = NBT.ListTag;
const Tag = NBT.Tag;
const ItemStack = @import("../item-stack.zig").ItemStack;
const ItemStackTrait = @import("../trait.zig").ItemStackTrait;
const DisplayNameComponent = @import("../components/display-name.zig");

pub const State = struct {};

fn getTagCompound(stack: *const ItemStack) ?CompoundTag {
    const nbt = stack.nbt orelse return null;
    const tag = nbt.get("tag") orelse return null;
    if (tag != .Compound) return null;
    return tag.Compound;
}

fn getDisplayCompound(stack: *const ItemStack) ?CompoundTag {
    const tag_compound = getTagCompound(stack) orelse return null;
    const display = tag_compound.get("display") orelse return null;
    if (display != .Compound) return null;
    return display.Compound;
}

fn ensureTagCompound(stack: *ItemStack) !*CompoundTag {
    if (stack.nbt == null) {
        stack.nbt = CompoundTag.init(stack.allocator, null);
    }
    var nbt = &(stack.nbt.?);
    if (!nbt.contains("tag")) {
        const name = try stack.allocator.dupe(u8, "tag");
        try nbt.add(.{ .Compound = CompoundTag.init(stack.allocator, name) });
    }
    const entry = nbt.value.getPtr("tag") orelse return error.Unexpected;
    return &entry.Compound;
}

fn ensureDisplayCompound(stack: *ItemStack) !*CompoundTag {
    const tag_compound = try ensureTagCompound(stack);
    if (!tag_compound.contains("display")) {
        const name = try stack.allocator.dupe(u8, "display");
        try tag_compound.add(.{ .Compound = CompoundTag.init(stack.allocator, name) });
    }
    const entry = tag_compound.value.getPtr("display") orelse return error.Unexpected;
    return &entry.Compound;
}

pub fn getComponentName(stack: *const ItemStack) ?[]const u8 {
    return DisplayNameComponent.getDisplayName(stack.item_type);
}

pub fn getDisplayName(stack: *const ItemStack) ?[]const u8 {
    const display = getDisplayCompound(stack) orelse return null;
    const tag = display.get("Name") orelse return null;
    if (tag != .String) return null;
    return tag.String.value;
}

pub fn setDisplayName(stack: *ItemStack, name: ?[]const u8) !void {
    const display = try ensureDisplayCompound(stack);
    if (name) |n| {
        const duped_name = try stack.allocator.dupe(u8, "Name");
        const duped_value = try stack.allocator.dupe(u8, n);
        try display.add(.{ .String = StringTag.init(duped_value, duped_name) });
    } else {
        var removed = display.value.fetchRemove("Name") orelse return;
        removed.value.deinit(stack.allocator);
    }
}

pub fn getLore(stack: *const ItemStack) []Tag {
    const display = getDisplayCompound(stack) orelse return &.{};
    const tag = display.get("Lore") orelse return &.{};
    if (tag != .List) return &.{};
    return tag.List.value;
}

pub fn setLore(stack: *ItemStack, lore: []const []const u8) !void {
    const display = try ensureDisplayCompound(stack);
    const tags = try stack.allocator.alloc(Tag, lore.len);
    for (lore, 0..) |text, i| {
        const duped_value = try stack.allocator.dupe(u8, text);
        tags[i] = .{ .String = StringTag.init(duped_value, null) };
    }
    const duped_name = try stack.allocator.dupe(u8, "Lore");
    try display.add(.{ .List = ListTag.init(tags, duped_name) });
}

fn onAttach(_: *State, stack: *ItemStack) void {
    _ = ensureDisplayCompound(stack) catch {};
}

fn onDetach(_: *State, stack: *ItemStack) void {
    if (stack.nbt) |*nbt| {
        const entry = nbt.value.getPtr("tag") orelse return;
        if (entry.* != .Compound) return;
        var removed = entry.Compound.value.fetchRemove("display") orelse return;
        removed.value.deinit(stack.allocator);
    }
}

pub const DisplayTrait = ItemStackTrait(State, .{
    .identifier = "display",
    .onAttach = onAttach,
    .onDetach = onDetach,
});
