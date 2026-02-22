const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;
const ClientData = @import("../login/types.zig").ClientData;
const SkinAnimation = @import("../login/types.zig").SkinAnimation;

pub const SerializedSkin = struct {
    pub fn write(stream: *BinaryStream, skin: *const ClientData, allocator: std.mem.Allocator) !void {
        try stream.writeVarString(skin.skin_id);
        try stream.writeVarString(skin.play_fab_id);

        try writeBase64Decoded(stream, skin.skin_resource_patch, allocator);

        try writeSkinImage(stream, skin.skin_image_width, skin.skin_image_height, skin.skin_data, allocator);

        try stream.writeUint32(@intCast(skin.animated_image_data.len), .Little);
        for (skin.animated_image_data) |anim| {
            try writeAnimation(stream, &anim, allocator);
        }

        try writeSkinImage(stream, skin.cape_image_width, skin.cape_image_height, skin.cape_data, allocator);

        try writeBase64Decoded(stream, skin.skin_geometry_data, allocator);
        try writeBase64Decoded(stream, skin.skin_geometry_data_engine_version, allocator);

        try stream.writeVarString(skin.skin_animation_data);
        try stream.writeVarString(skin.cape_id);
        try stream.writeVarString("");

        try stream.writeVarString(skin.arm_size);
        try stream.writeVarString(skin.skin_color);

        try stream.writeUint32(@intCast(skin.persona_pieces.len), .Little);
        for (skin.persona_pieces) |piece| {
            try stream.writeVarString(piece.piece_id);
            try stream.writeVarString(piece.piece_type);
            try stream.writeVarString(piece.pack_id);
            try stream.writeBool(piece.is_default);
            try stream.writeVarString(piece.product_id);
        }

        try stream.writeUint32(@intCast(skin.piece_tint_colours.len), .Little);
        for (skin.piece_tint_colours) |tint| {
            try stream.writeVarString(tint.piece_type);
            try stream.writeUint32(4, .Little);
            for (tint.colours) |colour| {
                try stream.writeVarString(colour);
            }
        }

        try stream.writeBool(skin.premium_skin);
        try stream.writeBool(skin.persona_skin);
        try stream.writeBool(skin.cape_on_classic_skin);
        try stream.writeBool(true);
        try stream.writeBool(true);
    }

    fn writeAnimation(stream: *BinaryStream, anim: *const SkinAnimation, allocator: std.mem.Allocator) !void {
        try stream.writeUint32(@intCast(anim.image_width), .Little);
        try stream.writeUint32(@intCast(anim.image_height), .Little);
        const decoded = try decodeBase64String(allocator, anim.image);
        defer allocator.free(decoded);
        try stream.writeVarInt(@intCast(decoded.len));
        try stream.write(decoded);
        try stream.writeUint32(@intCast(anim.animation_type), .Little);
        try stream.writeFloat32(@floatCast(anim.frames), .Little);
        try stream.writeUint32(@intCast(anim.expression_type), .Little);
    }

    fn writeSkinImage(stream: *BinaryStream, width: i64, height: i64, data: []const u8, allocator: std.mem.Allocator) !void {
        try stream.writeUint32(@intCast(width), .Little);
        try stream.writeUint32(@intCast(height), .Little);
        if (data.len == 0) {
            try stream.writeVarInt(0);
            return;
        }
        const decoded = try decodeBase64String(allocator, data);
        defer allocator.free(decoded);
        try stream.writeVarInt(@intCast(decoded.len));
        try stream.write(decoded);
    }

    fn writeBase64Decoded(stream: *BinaryStream, data: []const u8, allocator: std.mem.Allocator) !void {
        if (data.len == 0) {
            try stream.writeVarInt(0);
            return;
        }
        const decoded = try decodeBase64String(allocator, data);
        defer allocator.free(decoded);
        try stream.writeVarString(decoded);
    }

    fn decodeBase64String(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        if (data.len == 0) {
            return try allocator.alloc(u8, 0);
        }
        if (std.base64.standard.Decoder.calcSizeForSlice(data)) |decoded_len| {
            const decoded = try allocator.alloc(u8, decoded_len);
            if (std.base64.standard.Decoder.decode(decoded, data)) |_| {
                return decoded;
            } else |_| {
                allocator.free(decoded);
            }
        } else |_| {}
        if (std.base64.standard_no_pad.Decoder.calcSizeForSlice(data)) |decoded_len| {
            const decoded = try allocator.alloc(u8, decoded_len);
            if (std.base64.standard_no_pad.Decoder.decode(decoded, data)) |_| {
                return decoded;
            } else |_| {
                allocator.free(decoded);
            }
        } else |_| {}
        std.log.warn("[SKIN-B64] fallback to raw, len={d}", .{data.len});
        return try allocator.dupe(u8, data);
    }
};
