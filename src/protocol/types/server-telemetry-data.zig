const std = @import("std");
const BinaryStream = @import("BinaryStream").BinaryStream;

pub const ServerTelemetryData = struct {
    serverId: []const u8,
    scenarioId: []const u8,
    worldId: []const u8,
    ownerId: []const u8,

    pub fn init(serverId: []const u8, scenarioId: []const u8, worldId: []const u8, ownerId: []const u8) ServerTelemetryData {
        return ServerTelemetryData{
            .serverId = serverId,
            .scenarioId = scenarioId,
            .worldId = worldId,
            .ownerId = ownerId,
        };
    }

    pub fn read(stream: *BinaryStream) !ServerTelemetryData {
        const serverId = try stream.readVarString();
        const scenarioId = try stream.readVarString();
        const worldId = try stream.readVarString();
        const ownerId = try stream.readVarString();

        return ServerTelemetryData{
            .serverId = serverId,
            .scenarioId = scenarioId,
            .worldId = worldId,
            .ownerId = ownerId,
        };
    }

    pub fn write(stream: *BinaryStream, value: ServerTelemetryData) !void {
        try stream.writeVarString(value.serverId);
        try stream.writeVarString(value.scenarioId);
        try stream.writeVarString(value.worldId);
        try stream.writeVarString(value.ownerId);
    }

    pub fn deinit(self: *ServerTelemetryData, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};
