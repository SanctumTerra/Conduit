const std = @import("std");

pub const IdentityData = struct {
    xuid: []const u8,
    display_name: []const u8,
    identity: []const u8,
    sandbox_id: []const u8,
    title_id: []const u8,

    pub fn parse(allocator: std.mem.Allocator, json_value: std.json.Value) !IdentityData {
        const extra_data = json_value.object.get("extraData") orelse return error.MissingExtraData;

        const xuid = if (extra_data.object.get("XUID")) |x| try allocator.dupe(u8, x.string) else "";
        errdefer if (xuid.len > 0) allocator.free(xuid);

        const display_name = if (extra_data.object.get("displayName")) |n| try allocator.dupe(u8, n.string) else "";
        errdefer if (display_name.len > 0) allocator.free(display_name);

        const identity = if (extra_data.object.get("identity")) |i| try allocator.dupe(u8, i.string) else "";
        errdefer if (identity.len > 0) allocator.free(identity);

        const sandbox_id = if (extra_data.object.get("sandboxId")) |s| try allocator.dupe(u8, s.string) else "";
        errdefer if (sandbox_id.len > 0) allocator.free(sandbox_id);

        const title_id = if (extra_data.object.get("titleId")) |t| try allocator.dupe(u8, t.string) else "";
        errdefer if (title_id.len > 0) allocator.free(title_id);

        return IdentityData{
            .xuid = xuid,
            .display_name = display_name,
            .identity = identity,
            .sandbox_id = sandbox_id,
            .title_id = title_id,
        };
    }

    pub fn deinit(self: *IdentityData, allocator: std.mem.Allocator) void {
        if (self.xuid.len > 0) allocator.free(self.xuid);
        if (self.display_name.len > 0) allocator.free(self.display_name);
        if (self.identity.len > 0) allocator.free(self.identity);
        if (self.sandbox_id.len > 0) allocator.free(self.sandbox_id);
        if (self.title_id.len > 0) allocator.free(self.title_id);
    }
};

pub const ClientData = struct {
    skin_id: []const u8,
    skin_data: []const u8,
    skin_image_width: i64,
    skin_image_height: i64,
    skin_geometry_data: []const u8,
    skin_resource_patch: []const u8,
    skin_animation_data: []const u8,

    cape_id: []const u8,
    cape_data: []const u8,
    cape_image_width: i64,
    cape_image_height: i64,

    persona_skin: bool,
    premium_skin: bool,
    arm_size: []const u8,
    skin_color: []const u8,

    device_model: []const u8,
    device_os: i64,
    device_id: []const u8,
    game_version: []const u8,

    language_code: []const u8,
    server_address: []const u8,
    third_party_name: []const u8,
    platform_online_id: []const u8,
    self_signed_id: []const u8,

    ui_profile: i64,
    current_input_mode: i64,
    default_input_mode: i64,
    gui_scale: i64,

    pub fn parse(allocator: std.mem.Allocator, json_value: std.json.Value) !ClientData {
        const obj = json_value.object;

        const getString = struct {
            fn get(o: std.json.ObjectMap, key: []const u8, alloc: std.mem.Allocator) ![]const u8 {
                if (o.get(key)) |v| {
                    return try alloc.dupe(u8, v.string);
                }
                return "";
            }
        }.get;

        const getInt = struct {
            fn get(o: std.json.ObjectMap, key: []const u8) i64 {
                if (o.get(key)) |v| {
                    return v.integer;
                }
                return 0;
            }
        }.get;

        const getBool = struct {
            fn get(o: std.json.ObjectMap, key: []const u8) bool {
                if (o.get(key)) |v| {
                    return v.bool;
                }
                return false;
            }
        }.get;

        return ClientData{
            .skin_id = try getString(obj, "SkinId", allocator),
            .skin_data = try getString(obj, "SkinData", allocator),
            .skin_image_width = getInt(obj, "SkinImageWidth"),
            .skin_image_height = getInt(obj, "SkinImageHeight"),
            .skin_geometry_data = try getString(obj, "SkinGeometryData", allocator),
            .skin_resource_patch = try getString(obj, "SkinResourcePatch", allocator),
            .skin_animation_data = try getString(obj, "SkinAnimationData", allocator),

            .cape_id = try getString(obj, "CapeId", allocator),
            .cape_data = try getString(obj, "CapeData", allocator),
            .cape_image_width = getInt(obj, "CapeImageWidth"),
            .cape_image_height = getInt(obj, "CapeImageHeight"),

            .persona_skin = getBool(obj, "PersonaSkin"),
            .premium_skin = getBool(obj, "PremiumSkin"),
            .arm_size = try getString(obj, "ArmSize", allocator),
            .skin_color = try getString(obj, "SkinColor", allocator),

            .device_model = try getString(obj, "DeviceModel", allocator),
            .device_os = getInt(obj, "DeviceOS"),
            .device_id = try getString(obj, "DeviceId", allocator),
            .game_version = try getString(obj, "GameVersion", allocator),

            .language_code = try getString(obj, "LanguageCode", allocator),
            .server_address = try getString(obj, "ServerAddress", allocator),
            .third_party_name = try getString(obj, "ThirdPartyName", allocator),
            .platform_online_id = try getString(obj, "PlatformOnlineId", allocator),
            .self_signed_id = try getString(obj, "SelfSignedId", allocator),

            .ui_profile = getInt(obj, "UIProfile"),
            .current_input_mode = getInt(obj, "CurrentInputMode"),
            .default_input_mode = getInt(obj, "DefaultInputMode"),
            .gui_scale = getInt(obj, "GuiScale"),
        };
    }

    pub fn deinit(self: *ClientData, allocator: std.mem.Allocator) void {
        inline for (@typeInfo(ClientData).@"struct".fields) |field| {
            if (field.type == []const u8) {
                const value = @field(self, field.name);
                if (value.len > 0) allocator.free(value);
            }
        }
    }

    pub fn decodeSkinPixels(self: *const ClientData, allocator: std.mem.Allocator) ![]u8 {
        if (self.skin_data.len == 0) return error.NoSkinData;

        const decoder = std.base64.standard;
        const decoded_len = try decoder.Decoder.calcSizeForSlice(self.skin_data);
        const decoded = try allocator.alloc(u8, decoded_len);
        errdefer allocator.free(decoded);

        try decoder.Decoder.decode(decoded, self.skin_data);
        return decoded;
    }

    pub fn decodeCapePixels(self: *const ClientData, allocator: std.mem.Allocator) ![]u8 {
        if (self.cape_data.len == 0) return error.NoCapeData;

        const decoder = std.base64.standard;
        const decoded_len = try decoder.Decoder.calcSizeForSlice(self.cape_data);
        const decoded = try allocator.alloc(u8, decoded_len);
        errdefer allocator.free(decoded);

        try decoder.Decoder.decode(decoded, self.cape_data);
        return decoded;
    }

    pub fn getDeviceOSName(self: *const ClientData) []const u8 {
        return switch (self.device_os) {
            1 => "Android",
            2 => "iOS",
            3 => "macOS",
            4 => "FireOS",
            5 => "GearVR",
            6 => "Hololens",
            7 => "Windows 10",
            8 => "Windows",
            9 => "Dedicated",
            10 => "tvOS",
            11 => "PlayStation",
            12 => "Nintendo Switch",
            13 => "Xbox",
            14 => "Windows Phone",
            else => "Unknown",
        };
    }
};
