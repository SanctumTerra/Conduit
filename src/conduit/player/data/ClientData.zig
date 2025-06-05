const std = @import("std");
const LoginDecoder = @import("../../../protocol/list/login/types/LoginDecoder.zig").LoginDecoder;
const Logger = @import("Logger").Logger;

/// NOTE EACH UPDATE! Last Edit on 1.21.80
pub const ClientData = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,

    AnimatedImageData: ?[]const u8 = null,
    ArmSize: ?[]const u8 = null,
    CapeData: ?[]const u8 = null,
    CapeId: ?[]const u8 = null,
    CapeImageHeght: ?u16 = null,
    CapeImageWidth: ?u16 = null,
    CapeOnClassicSkin: ?bool = null,
    ClientRandomId: ?u64 = null,
    CompatibleWithClientSideChunkGeneration: ?bool = null,
    CurrentInputMode: ?[]const u8 = null,
    DefaultInputMode: ?[]const u8 = null,
    DeviceId: ?[]const u8 = null,
    DeviceModel: ?[]const u8 = null,
    DeviceOS: ?u8 = null,
    GameVersion: ?[]const u8 = null,
    GraphicsMode: ?u8 = null,
    GuiScale: ?u8 = null,
    IsEditorMode: ?bool = null,
    LanguageCode: ?[]const u8 = null,
    MaxViewDistance: ?u8 = null,
    MemoryTier: ?u8 = null,
    OverrideSkin: ?bool = null,
    PersonaPieces: ?[]const u8 = null,
    PersonaSkin: ?bool = null,
    PieceTintColors: ?[]const u8 = null,
    PlatformOfflineId: ?[]const u8 = null,
    PlatformOnlineId: ?[]const u8 = null,
    PlatformType: ?u8 = null,
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
    SkinImageHeight: ?u16 = null,
    SkinImageWidth: ?u16 = null,
    SkinResourcePatch: ?[]const u8 = null,
    ThirdPartyName: ?[]const u8 = null,
    ThirdPartyNameOnly: ?bool = null,
    TrustedSkin: ?bool = null,
    UIProfile: ?[]const u8 = null,

    needs_cleanup: bool = false,

    pub fn init(parent_allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = parent_allocator,
            .needs_cleanup = false,
        };
    }

    fn freeNullableSlice(self: *Self, slice_ptr: *?[]const u8) void {
        if (slice_ptr.*) |slice| {
            self.allocator.free(slice);
            slice_ptr.* = null;
        }
    }

    pub fn deinit(self: *Self) void {
        if (!self.needs_cleanup) return;

        self.freeNullableSlice(&self.AnimatedImageData);
        self.freeNullableSlice(&self.ArmSize);
        self.freeNullableSlice(&self.CapeData);
        self.freeNullableSlice(&self.CapeId);
        self.freeNullableSlice(&self.CurrentInputMode);
        self.freeNullableSlice(&self.DefaultInputMode);
        self.freeNullableSlice(&self.DeviceId);
        self.freeNullableSlice(&self.DeviceModel);
        self.freeNullableSlice(&self.GameVersion);
        self.freeNullableSlice(&self.LanguageCode);
        self.freeNullableSlice(&self.PersonaPieces);
        self.freeNullableSlice(&self.PieceTintColors);
        self.freeNullableSlice(&self.PlatformOfflineId);
        self.freeNullableSlice(&self.PlatformOnlineId);
        self.freeNullableSlice(&self.PlayFabId);
        self.freeNullableSlice(&self.SelfSignedId);
        self.freeNullableSlice(&self.ServerAddress);
        self.freeNullableSlice(&self.SkinAnimationData);
        self.freeNullableSlice(&self.SkinColor);
        self.freeNullableSlice(&self.SkinData);
        self.freeNullableSlice(&self.SkinGeometryData);
        self.freeNullableSlice(&self.SkinGeometryDataEngineVersion);
        self.freeNullableSlice(&self.SkinId);
        self.freeNullableSlice(&self.SkinResourcePatch);
        self.freeNullableSlice(&self.ThirdPartyName);
        self.freeNullableSlice(&self.UIProfile);

        self.needs_cleanup = false;
    }

    pub fn parseFromRaw(self: *Self, raw_token: []const u8) !void {
        var decoder = LoginDecoder.init(self.allocator);

        var decoded = try decoder.decode(raw_token);
        defer switch (decoded) {
            .payload_only => |*p| p.deinit(),
            .complete_token => |*t| t.deinit(),
        };

        switch (decoded) {
            .payload_only => |payload_wrapper| {
                if (payload_wrapper.payload.value == .object) {
                    try self.fromRaw(payload_wrapper.payload.value);
                } else {
                    return error.InvalidClientDataFormat;
                }
            },
            .complete_token => |token_wrapper| {
                if (token_wrapper.payload.value == .object) {
                    try self.fromRaw(token_wrapper.payload.value);
                } else {
                    return error.InvalidClientDataFormat;
                }
            },
        }
    }

    fn dupString(self: *Self, str: []const u8) !?[]const u8 {
        if (str.len == 0) return null;

        const new_str = try self.allocator.dupe(u8, str);
        self.needs_cleanup = true;
        return new_str;
    }

    pub fn fromRaw(self: *Self, raw: std.json.Value) !void {
        const FieldHandler = struct {
            fn setStringField(client_data: *Self, field_name: []const u8, value: []const u8) !void {
                const duped = try client_data.dupString(value);

                if (std.mem.eql(u8, field_name, "AnimatedImageData")) {
                    client_data.AnimatedImageData = duped;
                } else if (std.mem.eql(u8, field_name, "ArmSize")) {
                    client_data.ArmSize = duped;
                } else if (std.mem.eql(u8, field_name, "CapeData")) {
                    client_data.CapeData = duped;
                } else if (std.mem.eql(u8, field_name, "CapeId")) {
                    client_data.CapeId = duped;
                } else if (std.mem.eql(u8, field_name, "CurrentInputMode")) {
                    client_data.CurrentInputMode = duped;
                } else if (std.mem.eql(u8, field_name, "DefaultInputMode")) {
                    client_data.DefaultInputMode = duped;
                } else if (std.mem.eql(u8, field_name, "DeviceId")) {
                    client_data.DeviceId = duped;
                } else if (std.mem.eql(u8, field_name, "DeviceModel")) {
                    client_data.DeviceModel = duped;
                } else if (std.mem.eql(u8, field_name, "GameVersion")) {
                    client_data.GameVersion = duped;
                } else if (std.mem.eql(u8, field_name, "LanguageCode")) {
                    client_data.LanguageCode = duped;
                } else if (std.mem.eql(u8, field_name, "PersonaPieces")) {
                    client_data.PersonaPieces = duped;
                } else if (std.mem.eql(u8, field_name, "PieceTintColors")) {
                    client_data.PieceTintColors = duped;
                } else if (std.mem.eql(u8, field_name, "PlatformOfflineId")) {
                    client_data.PlatformOfflineId = duped;
                } else if (std.mem.eql(u8, field_name, "PlatformOnlineId")) {
                    client_data.PlatformOnlineId = duped;
                } else if (std.mem.eql(u8, field_name, "PlayFabId")) {
                    client_data.PlayFabId = duped;
                } else if (std.mem.eql(u8, field_name, "SelfSignedId")) {
                    client_data.SelfSignedId = duped;
                } else if (std.mem.eql(u8, field_name, "ServerAddress")) {
                    client_data.ServerAddress = duped;
                } else if (std.mem.eql(u8, field_name, "SkinAnimationData")) {
                    client_data.SkinAnimationData = duped;
                } else if (std.mem.eql(u8, field_name, "SkinColor")) {
                    client_data.SkinColor = duped;
                } else if (std.mem.eql(u8, field_name, "SkinData")) {
                    client_data.SkinData = duped;
                } else if (std.mem.eql(u8, field_name, "SkinGeometryData")) {
                    client_data.SkinGeometryData = duped;
                } else if (std.mem.eql(u8, field_name, "SkinGeometryDataEngineVersion")) {
                    client_data.SkinGeometryDataEngineVersion = duped;
                } else if (std.mem.eql(u8, field_name, "SkinId")) {
                    client_data.SkinId = duped;
                } else if (std.mem.eql(u8, field_name, "SkinResourcePatch")) {
                    client_data.SkinResourcePatch = duped;
                } else if (std.mem.eql(u8, field_name, "ThirdPartyName")) {
                    client_data.ThirdPartyName = duped;
                } else if (std.mem.eql(u8, field_name, "UIProfile")) {
                    client_data.UIProfile = duped;
                }
            }
        };

        for (raw.object.keys()) |key| {
            const value = raw.object.get(key) orelse continue;

            switch (value) {
                .string => |str| {
                    try FieldHandler.setStringField(self, key, str);
                },
                .integer => |int| {
                    if (std.mem.eql(u8, key, "CapeImageHeght")) {
                        self.CapeImageHeght = @intCast(int);
                    } else if (std.mem.eql(u8, key, "CapeImageWidth")) {
                        self.CapeImageWidth = @intCast(int);
                    } else if (std.mem.eql(u8, key, "ClientRandomId")) {
                        self.ClientRandomId = @intCast(int);
                    } else if (std.mem.eql(u8, key, "DeviceOS")) {
                        self.DeviceOS = @intCast(int);
                    } else if (std.mem.eql(u8, key, "GraphicsMode")) {
                        self.GraphicsMode = @intCast(int);
                    } else if (std.mem.eql(u8, key, "GuiScale")) {
                        self.GuiScale = @intCast(int);
                    } else if (std.mem.eql(u8, key, "MaxViewDistance")) {
                        self.MaxViewDistance = @intCast(int);
                    } else if (std.mem.eql(u8, key, "MemoryTier")) {
                        self.MemoryTier = @intCast(int);
                    } else if (std.mem.eql(u8, key, "PlatformType")) {
                        self.PlatformType = @intCast(int);
                    } else if (std.mem.eql(u8, key, "SkinImageHeight")) {
                        self.SkinImageHeight = @intCast(int);
                    } else if (std.mem.eql(u8, key, "SkinImageWidth")) {
                        self.SkinImageWidth = @intCast(int);
                    }
                },
                .bool => |boolean| {
                    if (std.mem.eql(u8, key, "CapeOnClassicSkin")) {
                        self.CapeOnClassicSkin = boolean;
                    } else if (std.mem.eql(u8, key, "CompatibleWithClientSideChunkGeneration")) {
                        self.CompatibleWithClientSideChunkGeneration = boolean;
                    } else if (std.mem.eql(u8, key, "IsEditorMode")) {
                        self.IsEditorMode = boolean;
                    } else if (std.mem.eql(u8, key, "OverrideSkin")) {
                        self.OverrideSkin = boolean;
                    } else if (std.mem.eql(u8, key, "PersonaSkin")) {
                        self.PersonaSkin = boolean;
                    } else if (std.mem.eql(u8, key, "PremiumSkin")) {
                        self.PremiumSkin = boolean;
                    } else if (std.mem.eql(u8, key, "ThirdPartyNameOnly")) {
                        self.ThirdPartyNameOnly = boolean;
                    } else if (std.mem.eql(u8, key, "TrustedSkin")) {
                        self.TrustedSkin = boolean;
                    }
                },
                else => {
                    Logger.DEBUG("Unhandled JSON value type for key: {s}", .{key});
                },
            }
        }
    }
};
