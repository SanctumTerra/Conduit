const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ClientData = @import("../login/types.zig").ClientData;

pub const SerializedSkin = struct {
    pub fn write(stream: *BinaryStream, skin: *const ClientData, allocator: std.mem.Allocator) !void {
        try stream.writeVarString(skin.skin_id);
        try stream.writeVarString("");

        const resource_patch = try decodeBase64String(allocator, skin.skin_resource_patch);
        defer allocator.free(resource_patch);
        try stream.writeVarString(resource_patch);

        try writeSkinImage(stream, skin.skin_image_width, skin.skin_image_height, skin.skin_data, allocator);

        try stream.writeUint32(0, .Little);

        try writeSkinImage(stream, skin.cape_image_width, skin.cape_image_height, skin.cape_data, allocator);

        const geometry_data = try decodeBase64String(allocator, skin.skin_geometry_data);
        defer allocator.free(geometry_data);
        try stream.writeVarString(geometry_data);

        try stream.writeVarString("");
        try stream.writeVarString(skin.skin_animation_data);
        try stream.writeVarString(skin.cape_id);

        const full_id = try std.fmt.allocPrint(allocator, "{s}{s}", .{ skin.skin_id, skin.cape_id });
        defer allocator.free(full_id);
        try stream.writeVarString(full_id);

        try stream.writeVarString(skin.arm_size);
        try stream.writeVarString(skin.skin_color);

        try stream.writeUint32(0, .Little);
        try stream.writeUint32(0, .Little);

        try stream.writeBool(skin.premium_skin);
        try stream.writeBool(skin.persona_skin);
        try stream.writeBool(false);
        try stream.writeBool(false);
        try stream.writeBool(false);
    }

    fn writeSkinImage(stream: *BinaryStream, width: i64, height: i64, data: []const u8, allocator: std.mem.Allocator) !void {
        try stream.writeUint32(@intCast(width), .Little);
        try stream.writeUint32(@intCast(height), .Little);
        if (data.len == 0) {
            try stream.writeVarInt(0);
            return;
        }
        const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data) catch {
            try stream.writeVarInt(@intCast(data.len));
            try stream.write(data);
            return;
        };
        const decoded = try allocator.alloc(u8, decoded_len);
        defer allocator.free(decoded);
        std.base64.standard.Decoder.decode(decoded, data) catch {
            try stream.writeVarInt(@intCast(data.len));
            try stream.write(data);
            return;
        };
        try stream.writeVarInt(@intCast(decoded.len));
        try stream.write(decoded);
    }

    fn decodeBase64String(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        if (data.len == 0) {
            return try allocator.alloc(u8, 0);
        }
        const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data) catch {
            return try allocator.dupe(u8, data);
        };
        const decoded = try allocator.alloc(u8, decoded_len);
        std.base64.standard.Decoder.decode(decoded, data) catch {
            allocator.free(decoded);
            return try allocator.dupe(u8, data);
        };
        return decoded;
    }
};
