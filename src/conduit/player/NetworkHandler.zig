pub const NetworkHandler = struct {
    compression_method: CompressionMethod,
    compression_threshold: u16 = 1,
    compression_enabled: bool = false,
    encryption_enabled: bool = false,

    pub fn init() !NetworkHandler {
        return NetworkHandler{
            .compression_method = .NotPresent,
            .compression_threshold = 1,
            .compression_enabled = false,
            .encryption_enabled = false,
        };
    }

    pub fn handle(self: *NetworkHandler, player: *Player, buffer: []const u8) void {
        _ = self;
        const decompressed_packet = NetworkHandler.decompressPacket(buffer) catch |err| {
            Logger.ERROR("Failed to decompress packet: {any}", .{err});
            return;
        };
        const packets = Framer.unframe(decompressed_packet) catch |err| {
            Logger.ERROR("Failed to unframe packet: {any}", .{err});
            return;
        };
        // defer CAllocator.get().free(packets);
        defer Framer.freeUnframedData(packets);
        for (packets) |packet| {
            switch (packet[0]) {
                Packets.RequestNetworkSettings => {
                    RequestNetworkHandler.handle(player, packet) catch |err| {
                        Logger.ERROR("Failed to handle RequestNetworkSettings: {any}", .{err});
                    };
                },
                Packets.Login => {
                    LoginHandler.handle(player, packet) catch |err| {
                        Logger.ERROR("Failed to handle Login: {any}", .{err});
                    };
                },
                Packets.ResourcePackResponse => {
                    ResourcePackResponseHandler.handle(player, packet) catch |err| {
                        Logger.ERROR("Failed to handle ResourcePackResponse: {any}", .{err});
                    };
                },
                Packets.RequestChunkRadius => {
                    RequestChunkRadiusHandler.handle(player, packet) catch |err| {
                        Logger.ERROR("Failed to handle RequestChunkRadius: {any}", .{err});
                    };
                },
                else => {
                    Logger.WARN("Unhandled Game packet: {d}", .{packet[0]});
                },
            }
        }
        defer CAllocator.get().free(decompressed_packet);
    }

    // In NetworkHandler.zig
    pub fn compressPacket(data: []const u8, method: CompressionMethod) ![]const u8 {
        if (data.len == 0) return error.InvalidData;
        Logger.DEBUG("Using compression method: {any}", .{method});

        switch (method) {
            .NotPresent => {
                return try CAllocator.get().dupe(u8, data);
            },
            .None => {
                var result = std.ArrayList(u8).init(CAllocator.get());
                defer result.deinit();
                try result.append(@intFromEnum(CompressionMethod.None));
                try result.appendSlice(data);
                return try CAllocator.get().dupe(u8, result.items);
            },
            .Zlib => {
                Logger.DEBUG("Compressing Zlib data ({d} bytes)", .{data.len});
                var result = std.ArrayList(u8).init(CAllocator.get());
                defer result.deinit();
                try result.append(@intFromEnum(CompressionMethod.Zlib));

                var compressed_buffer = std.ArrayList(u8).init(CAllocator.get());
                defer compressed_buffer.deinit();

                var compressor = try std.compress.flate.compressor(compressed_buffer.writer(), .{});
                try compressor.writer().writeAll(data);
                try compressor.finish();

                try result.appendSlice(compressed_buffer.items);
                return try CAllocator.get().dupe(u8, result.items);
            },
            .Snappy => {
                Logger.ERROR("Snappy compression not implemented", .{});
                return error.UnsupportedCompressionMethod;
            },
        }
    }

    /// This returns an owned slice of Decompressed packet.
    pub fn decompressPacket(packet: []const u8) ![]const u8 {
        if (packet.len < 1) return error.InvalidPacket;
        // skip 1 byete aka GameByte
        const decrypted = packet[1..];
        const compression_byte = decrypted[0];
        const compressionMethod: CompressionMethod = switch (compression_byte) {
            @intFromEnum(CompressionMethod.NotPresent) => .NotPresent,
            @intFromEnum(CompressionMethod.None) => .None,
            @intFromEnum(CompressionMethod.Zlib) => .Zlib,
            @intFromEnum(CompressionMethod.Snappy) => .Snappy,
            else => .NotPresent,
        };
        {}

        if (compressionMethod == .NotPresent) {
            return try CAllocator.get().dupe(u8, decrypted);
        }
        const compressed_data = decrypted[1..];

        switch (compressionMethod) {
            .Zlib => {
                Logger.DEBUG("Decompressing Zlib data ({d} bytes)", .{compressed_data.len});
                if (compressed_data.len < 1) {
                    Logger.ERROR("Invalid compressed data: empty", .{});
                    return error.InvalidCompressedData;
                }

                var decompression_buffer = std.ArrayList(u8).init(CAllocator.get());
                defer decompression_buffer.deinit();

                var compressed_stream = std.io.fixedBufferStream(compressed_data);
                var decompressor = std.compress.flate.inflate.decompressor(.raw, compressed_stream.reader());

                decompressor.reader().readAllArrayList(&decompression_buffer, std.math.maxInt(usize)) catch |err| {
                    Logger.ERROR("Flate decompression failed: {any}", .{err});
                    return err;
                };

                return try CAllocator.get().dupe(u8, decompression_buffer.items);
            },
            .None => {
                // No compression, just use the data after the compression method byte
                return try CAllocator.get().dupe(u8, compressed_data);
            },
            else => {
                Logger.ERROR("Unsupported compression method: {any}", .{compressionMethod});
                return error.UnsupportedCompressionMethod;
            },
        }
        return decrypted;
    }
};

const LoginHandler = @import("./handlers/LoginHandler.zig");
const RequestNetworkHandler = @import("./handlers/RequestNetworkHandler.zig");
const Framer = @import("../../protocol/misc/Framer.zig").Framer;
const Packets = @import("../../protocol/enums/Packets.zig").Packets;
const CompressionMethod = @import("../../protocol/enums/CompressionMethod.zig").CompressionMethod;
const CAllocator = @import("CAllocator");
const Logger = @import("Logger").Logger;
const Player = @import("./Player.zig").Player;
const std = @import("std");
const ResourcePackResponseHandler = @import("./handlers/ResourcePackResponseHandler.zig");
const RequestChunkRadiusHandler = @import("./handlers/RequestChunkRadiusHandler.zig");
