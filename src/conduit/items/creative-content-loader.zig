const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");
const ItemType = @import("./item-type.zig").ItemType;

pub const CreativeContentData = struct {
    serialized: []const u8,
    allocator: std.mem.Allocator,
    group_count: usize,
    item_count: usize,

    pub fn deinit(self: *CreativeContentData) void {
        self.allocator.free(self.serialized);
    }
};

pub fn loadCreativeContent(allocator: std.mem.Allocator) !CreativeContentData {
    var stream = BinaryStream.init(allocator, null, null);
    defer stream.deinit();

    try stream.writeVarInt(Protocol.Packet.CreativeContent);

    const group_count = try writeGroups(&stream, allocator);
    const item_count = try writeItems(&stream, allocator);

    const buf = stream.getBuffer();
    const serialized = try allocator.alloc(u8, buf.len);
    @memcpy(serialized, buf);

    return .{
        .serialized = serialized,
        .allocator = allocator,
        .group_count = group_count,
        .item_count = item_count,
    };
}

fn writeGroups(stream: *BinaryStream, allocator: std.mem.Allocator) !usize {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        Protocol.Data.creative_groups_json,
        .{},
    );
    defer parsed.deinit();

    const arr = if (parsed.value == .array) parsed.value.array.items else return error.InvalidJsonFormat;

    try stream.writeVarInt(@intCast(arr.len));

    var count: usize = 0;
    for (arr) |entry| {
        if (entry != .object) continue;
        const obj = entry.object;

        const category_int = if (obj.get("category")) |c| if (c == .integer) @as(i32, @intCast(c.integer)) else continue else continue;
        const name = if (obj.get("name")) |n| if (n == .string) n.string else continue else continue;
        const icon_id = if (obj.get("icon")) |i| if (i == .string) i.string else continue else continue;

        const item_type = ItemType.get(icon_id);
        const network_id: i32 = if (item_type) |it| it.network_id else 0;

        try stream.writeInt32(category_int, .Little);
        try stream.writeVarString(name);
        try stream.writeZigZag(network_id);
        if (network_id != 0) {
            try stream.writeUint16(1, .Little);
            try stream.writeVarInt(0);
            try stream.writeZigZag(0);
            try stream.writeVarInt(0);
        }
        count += 1;
    }

    return count;
}

fn writeItems(stream: *BinaryStream, allocator: std.mem.Allocator) !usize {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        Protocol.Data.creative_content_json,
        .{},
    );
    defer parsed.deinit();

    const arr = if (parsed.value == .array) parsed.value.array.items else return error.InvalidJsonFormat;

    try stream.writeVarInt(@intCast(arr.len));

    var count: usize = 0;
    for (arr, 0..) |entry, i| {
        if (entry != .object) continue;
        const obj = entry.object;

        const instance_b64 = if (obj.get("instance")) |inst| if (inst == .string) inst.string else continue else continue;
        const group_index = if (obj.get("groupIndex")) |g| if (g == .integer) @as(u32, @intCast(g.integer)) else 0 else 0;

        const raw = decodeBase64(allocator, instance_b64) catch continue;
        defer allocator.free(raw);

        try stream.writeVarInt(@intCast(i + 1));
        try stream.write(raw);
        try stream.writeVarInt(group_index);
        count += 1;
    }

    return count;
}

fn decodeBase64(allocator: std.mem.Allocator, b64: []const u8) ![]const u8 {
    if (b64.len == 0) return error.EmptyInput;
    const decoder = std.base64.standard.decoderWithIgnore("");
    const size = try decoder.calcSizeUpperBound(b64.len);
    const buf = try allocator.alloc(u8, size);
    const decoded_len = try decoder.decode(buf, b64);
    return try allocator.realloc(buf, decoded_len);
}
