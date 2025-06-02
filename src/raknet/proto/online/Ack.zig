const std = @import("std");
const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;

pub const Ack = struct {
    sequences: []u32,
    allocator: std.mem.Allocator,

    pub fn init(sequences: []const u32, allocator: std.mem.Allocator) !Ack {
        const seq = try allocator.alloc(u32, sequences.len);
        @memcpy(seq, sequences);
        return Ack{
            .sequences = seq,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Ack) void {
        self.allocator.free(self.sequences);
    }

    /// DEALLOCATE THE RETURNED STRUCT AFTER USE
    pub fn deserialize(data: []const u8) Ack {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();
        // It fails with VarInt
        _ = stream.readUint8();
        const count = stream.readUint16(.Big);

        var sequences = std.ArrayList(u32).init(CAllocator.get());

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const range = stream.readBool();
            if (range) {
                const value = stream.readUint24(.Little);
                sequences.append(value) catch |err| {
                    Logger.ERROR("Failed to append sequence value: {}", .{err});
                    continue;
                };
            } else {
                const start = stream.readUint24(.Little);
                const end = stream.readUint24(.Little);
                var j = start;
                while (j <= end) : (j += 1) {
                    sequences.append(j) catch |err| {
                        Logger.ERROR("Failed to append sequence range value: {}", .{err});
                        break;
                    };
                }
            }
        }

        const result = Ack.init(sequences.items, CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to initialize Ack: {}", .{err});
            sequences.deinit();
            return Ack{
                .sequences = &[_]u32{},
                .allocator = CAllocator.get(),
            };
        };
        sequences.deinit();
        return result;
    }

    pub fn serialize(self: *const Ack) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();
        // It fails with VarInt
        stream.writeUint8(Packets.Ack);

        // Sort sequences for easier range detection
        std.mem.sort(u32, self.sequences, {}, comptime std.sort.asc(u32));

        var records: u16 = 0;
        var secondStream = BinaryStream.init(buffer, 0);
        defer secondStream.deinit();

        const count = self.sequences.len;
        if (count > 0) {
            var cursor: usize = 0;
            var start = self.sequences[0];
            var last = self.sequences[0];

            while (cursor < count - 1) {
                cursor += 1;
                const current = self.sequences[cursor];
                const diff = current - last;

                if (diff == 1) {
                    last = current;
                } else {
                    if (start == last) {
                        secondStream.writeBool(true);
                        secondStream.writeUint24(@as(u24, @truncate(start)), .Little);
                    } else {
                        secondStream.writeBool(false);
                        secondStream.writeUint24(@as(u24, @truncate(start)), .Little);
                        secondStream.writeUint24(@as(u24, @truncate(last)), .Little);
                    }
                    records += 1;
                    start = current;
                    last = current;
                }
            }

            if (start == last) {
                secondStream.writeBool(true);
                secondStream.writeUint24(@as(u24, @truncate(start)), .Little);
            } else {
                secondStream.writeBool(false);
                secondStream.writeUint24(@as(u24, @truncate(start)), .Little);
                secondStream.writeUint24(@as(u24, @truncate(last)), .Little);
            }
            records += 1;
        }

        stream.writeUint16(records, .Big);
        stream.write(secondStream.buffer.items);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize Ack: {}", .{err});
            return &[_]u8{};
        };
    }
};
