const std = @import("std");

pub const AnimatedImageData = struct {
    AnimationExpression: i32,
    Frames: i32,
    Image: []const u8,
    ImageHeight: i32,
    ImageWidth: i32,
    Type: i32,
};

pub const PersonaPiece = struct {
    IsDefault: bool,
    PackId: []const u8,
    PieceId: []const u8,
    PieceType: []const u8,
    ProductId: []const u8,
};

pub const PieceTintColor = struct {
    Colors: [][]const u8,
    PieceType: []const u8,
};

pub const ClientData = struct {
    const Self = @This();
    allocator: std.mem.Allocator,

    AnimatedImageData: ?[]AnimatedImageData = null,
    ArmSize: ?[]const u8 = null,
    CapeData: ?[]const u8 = null,
    CapeId: ?[]const u8 = null,
    CapeImageHeight: ?i32 = null,
    CapeImageWidth: ?i32 = null,
    CapeOnClassicSkin: ?bool = null,
    ClientRandomId: ?i64 = null,
    CompatibleWithClientSideChunkGen: ?bool = null,
    CurrentInputMode: ?i32 = null,
    DefaultInputMode: ?i32 = null,
    DeviceId: ?[]const u8 = null,
    DeviceModel: ?[]const u8 = null,
    DeviceOS: ?i32 = null,
    GameVersion: ?[]const u8 = null,
    GuiScale: ?i32 = null,
    IsEditorMode: ?bool = null,
    LanguageCode: ?[]const u8 = null,
    MaxViewDistance: ?i32 = null,
    MemoryTier: ?i32 = null,
    OverrideSkin: ?bool = null,
    PersonaPieces: ?[]PersonaPiece = null,
    PersonaSkin: ?bool = null,
    PieceTintColors: ?[]PieceTintColor = null,
    PlatformOfflineId: ?[]const u8 = null,
    PlatformOnlineId: ?[]const u8 = null,
    PlayFabId: ?[]const u8 = null,
    PremiumSkin: ?bool = null,
    SelfSignedId: ?[]const u8 = null,
    ServerAddress: ?[]const u8 = null,
    SkinAnimationData: ?[]const u8 = null,
    SkinColor: ?[]const u8 = null,
    SkinData: ?[]const u8 = null,
    SkinGeometryData: ?[]const u8 = null,
    SkinGeometryDataEngineVersion: ?[]const u8 = null,
    SkinId: ?[]const u8 = null,
    SkinImageHeight: ?i32 = null,
    SkinImageWidth: ?i32 = null,
    SkinResourcePatch: ?[]const u8 = null,
    ThirdPartyName: ?[]const u8 = null,
    ThirdPartyNameOnly: ?bool = null,
    TrustedSkin: ?bool = null,
    UIProfile: ?i32 = null,

    pub fn fromJson(allocator: std.mem.Allocator, json_value: std.json.Value) !Self {
        if (json_value != .object) return error.InvalidClientData;

        var self = Self{ .allocator = allocator };
        const obj = json_value.object;

        // Populate all fields directly
        self.ArmSize = Self.getStringField(allocator, obj, "ArmSize");
        self.CapeData = Self.getStringField(allocator, obj, "CapeData");
        self.CapeId = Self.getStringField(allocator, obj, "CapeId");
        self.CapeImageHeight = Self.getIntField(obj, "CapeImageHeight", i32);
        self.CapeImageWidth = Self.getIntField(obj, "CapeImageWidth", i32);
        self.CapeOnClassicSkin = Self.getBoolField(obj, "CapeOnClassicSkin");
        self.ClientRandomId = Self.getIntField(obj, "ClientRandomId", i64);
        self.CompatibleWithClientSideChunkGen = Self.getBoolField(obj, "CompatibleWithClientSideChunkGen");
        self.CurrentInputMode = Self.getIntField(obj, "CurrentInputMode", i32);
        self.DefaultInputMode = Self.getIntField(obj, "DefaultInputMode", i32);
        self.DeviceId = Self.getStringField(allocator, obj, "DeviceId");
        self.DeviceModel = Self.getStringField(allocator, obj, "DeviceModel");
        self.DeviceOS = Self.getIntField(obj, "DeviceOS", i32);
        self.GameVersion = Self.getStringField(allocator, obj, "GameVersion");
        self.GuiScale = Self.getIntField(obj, "GuiScale", i32);
        self.IsEditorMode = Self.getBoolField(obj, "IsEditorMode");
        self.LanguageCode = Self.getStringField(allocator, obj, "LanguageCode");
        self.MaxViewDistance = Self.getIntField(obj, "MaxViewDistance", i32);
        self.MemoryTier = Self.getIntField(obj, "MemoryTier", i32);
        self.OverrideSkin = Self.getBoolField(obj, "OverrideSkin");
        self.PersonaSkin = Self.getBoolField(obj, "PersonaSkin");
        self.PlatformOfflineId = Self.getStringField(allocator, obj, "PlatformOfflineId");
        self.PlatformOnlineId = Self.getStringField(allocator, obj, "PlatformOnlineId");
        self.PlayFabId = Self.getStringField(allocator, obj, "PlayFabId");
        self.PremiumSkin = Self.getBoolField(obj, "PremiumSkin");
        self.SelfSignedId = Self.getStringField(allocator, obj, "SelfSignedId");
        self.ServerAddress = Self.getStringField(allocator, obj, "ServerAddress");
        self.SkinAnimationData = Self.getStringField(allocator, obj, "SkinAnimationData");
        self.SkinColor = Self.getStringField(allocator, obj, "SkinColor");
        self.SkinData = Self.getStringField(allocator, obj, "SkinData");
        self.SkinGeometryData = Self.getStringField(allocator, obj, "SkinGeometryData");
        self.SkinGeometryDataEngineVersion = Self.getStringField(allocator, obj, "SkinGeometryDataEngineVersion");
        self.SkinId = Self.getStringField(allocator, obj, "SkinId");
        self.SkinImageHeight = Self.getIntField(obj, "SkinImageHeight", i32);
        self.SkinImageWidth = Self.getIntField(obj, "SkinImageWidth", i32);
        self.SkinResourcePatch = Self.getStringField(allocator, obj, "SkinResourcePatch");
        self.ThirdPartyName = Self.getStringField(allocator, obj, "ThirdPartyName");
        self.ThirdPartyNameOnly = Self.getBoolField(obj, "ThirdPartyNameOnly");
        self.TrustedSkin = Self.getBoolField(obj, "TrustedSkin");
        self.UIProfile = Self.getIntField(obj, "UIProfile", i32);

        return self;
    }

    fn getStringField(allocator: std.mem.Allocator, obj: std.json.ObjectMap, field_name: []const u8) ?[]const u8 {
        if (obj.get(field_name)) |val| {
            if (val == .string) {
                return allocator.dupe(u8, val.string) catch null;
            }
        }
        return null;
    }

    fn getIntField(obj: std.json.ObjectMap, field_name: []const u8, comptime T: type) ?T {
        if (obj.get(field_name)) |val| {
            return switch (val) {
                .integer => @intCast(val.integer),
                .number_string => std.fmt.parseInt(T, val.number_string, 10) catch null,
                else => null,
            };
        }
        return null;
    }

    fn getBoolField(obj: std.json.ObjectMap, field_name: []const u8) ?bool {
        if (obj.get(field_name)) |val| {
            if (val == .bool) return val.bool;
        }
        return null;
    }

    pub fn deinit(self: *Self) void {
        // Free all allocated strings
        if (self.ArmSize) |val| self.allocator.free(val);
        if (self.CapeData) |val| self.allocator.free(val);
        if (self.CapeId) |val| self.allocator.free(val);
        if (self.DeviceId) |val| self.allocator.free(val);
        if (self.DeviceModel) |val| self.allocator.free(val);
        if (self.GameVersion) |val| self.allocator.free(val);
        if (self.LanguageCode) |val| self.allocator.free(val);
        if (self.PlatformOfflineId) |val| self.allocator.free(val);
        if (self.PlatformOnlineId) |val| self.allocator.free(val);
        if (self.PlayFabId) |val| self.allocator.free(val);
        if (self.SelfSignedId) |val| self.allocator.free(val);
        if (self.ServerAddress) |val| self.allocator.free(val);
        if (self.SkinAnimationData) |val| self.allocator.free(val);
        if (self.SkinColor) |val| self.allocator.free(val);
        if (self.SkinData) |val| self.allocator.free(val);
        if (self.SkinGeometryData) |val| self.allocator.free(val);
        if (self.SkinGeometryDataEngineVersion) |val| self.allocator.free(val);
        if (self.SkinId) |val| self.allocator.free(val);
        if (self.SkinResourcePatch) |val| self.allocator.free(val);
        if (self.ThirdPartyName) |val| self.allocator.free(val);

        // Free arrays if allocated
        if (self.AnimatedImageData) |arr| self.allocator.free(arr);
        if (self.PersonaPieces) |arr| self.allocator.free(arr);
        if (self.PieceTintColors) |arr| self.allocator.free(arr);
    }
};
