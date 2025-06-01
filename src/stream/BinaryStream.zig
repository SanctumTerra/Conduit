const std = @import("std");
const Callocator = @import("CAllocator");
const Logger = @import("Logger").Logger;

pub const Endianess = enum {
    Big,
    Little,
};

pub const MagicBytes: [16]u8 = [16]u8{
    0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe,
    0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78,
};

pub const BinaryStream = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    position: usize,

    pub fn init(allocator: std.mem.Allocator, buffer: []const u8, position: usize) BinaryStream {
        // Create ArrayList and append the buffer contents
        var array_list = std.ArrayList(u8).init(allocator);
        array_list.appendSlice(buffer) catch |err| {
            Logger.ERROR("Failed to initialize binary stream: {}", .{err});
            return BinaryStream{
                .allocator = allocator,
                .position = position,
                .buffer = std.ArrayList(u8).init(allocator),
            };
        };

        return BinaryStream{
            .allocator = allocator,
            .position = position,
            .buffer = array_list,
        };
    }

    // Self explanatory, deinitializes the stream.
    pub fn deinit(self: *BinaryStream) void {
        self.buffer.deinit();
    }

    pub fn toOwnedSlice(self: *BinaryStream) ![]u8 {
        const result = try self.allocator.alloc(u8, self.buffer.items.len);
        @memcpy(result, self.buffer.items);
        self.buffer.clearRetainingCapacity();
        return result;
    }

    pub fn skip(self: *BinaryStream, length: usize) void {
        self.position += length;
    }

    /// Reads a specified number of bytes from the stream.
    /// If there are not enough bytes left, returns as many as possible.
    pub fn read(self: *BinaryStream, length: usize) []const u8 {
        if (self.position + length > self.buffer.items.len) {
            const safe_length = if (self.position < self.buffer.items.len)
                self.buffer.items.len - self.position
            else
                0;

            const value = if (safe_length > 0)
                self.buffer.items[self.position..][0..safe_length]
            else
                &[_]u8{};

            self.position += safe_length;
            return value;
        }

        const value = self.buffer.items[self.position .. self.position + length];
        self.position += length;
        return value;
    }

    pub fn getRemaining(self: *BinaryStream) []u8 {
        return self.buffer.items[self.position..];
    }

    pub fn readRemaining(self: *BinaryStream) []u8 {
        const value = self.buffer.items[self.position..];
        self.position = self.buffer.items.len;
        return value;
    }

    /// Writes a value to the binary stream.
    /// If the value cannot be written, the stream is not modified.
    pub fn write(self: *BinaryStream, value: []const u8) void {
        // Check if the value is overlapping with our buffer
        const our_buffer_ptr = if (self.buffer.items.len > 0) @intFromPtr(&self.buffer.items[0]) else 0;
        const value_ptr = if (value.len > 0) @intFromPtr(&value[0]) else 0;
        const may_alias = value_ptr >= our_buffer_ptr and
            value_ptr < our_buffer_ptr + self.buffer.items.len;

        // If there's a potential overlap, make a copy first
        if (may_alias) {
            const temp = self.allocator.dupe(u8, value) catch |err| {
                Logger.ERROR("Failed to copy overlapping buffer: {}", .{err});
                return;
            };
            defer self.allocator.free(temp);

            // Now do the actual write with the safe copy
            self.writeNonAliasing(temp);
            return;
        }

        // Normal case - just write directly
        self.writeNonAliasing(value);
    }

    fn writeNonAliasing(self: *BinaryStream, value: []const u8) void {
        // Ensure we have enough space in the buffer
        if (self.position + value.len > self.buffer.items.len) {
            self.buffer.resize(self.position + value.len) catch |err| {
                Logger.ERROR("Failed to resize binary stream buffer: {}", .{err});
                return;
            };
        }
        @memcpy(self.buffer.items[self.position .. self.position + value.len], value);
        self.position += value.len;
    }

    pub fn readUint8(self: *BinaryStream) u8 {
        const bytes = self.read(1);
        if (bytes.len == 0) {
            Logger.ERROR("Cannot read uint8: position out of bounds", .{});
            return 0;
        }
        return bytes[0];
    }

    pub fn writeUint8(self: *BinaryStream, value: u8) void {
        if (self.position >= self.buffer.items.len) {
            self.buffer.append(value) catch |err| {
                Logger.ERROR("Error appending value to buffer: {}", .{err});
                return;
            };
        } else {
            self.buffer.items[self.position] = value;
        }
        self.position += 1;
    }

    pub fn readUint16(self: *BinaryStream, endianess: ?Endianess) u16 {
        const bytes = self.read(2);
        if (bytes.len < 2) {
            Logger.ERROR("Cannot read uint16: not enough bytes", .{});
            return 0;
        }
        const value = switch (endianess orelse .Big) {
            .Little => @as(u16, @intCast(bytes[0])) | (@as(u16, @intCast(bytes[1])) << 8),
            .Big => (@as(u16, @intCast(bytes[0])) << 8) | @as(u16, @intCast(bytes[1])),
        };
        return value;
    }

    pub fn writeUint16(self: *BinaryStream, value: u16, endianess: ?Endianess) void {
        var bytes: [2]u8 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bytes[0] = @intCast(value & 0xFF);
                bytes[1] = @intCast((value >> 8) & 0xFF);
            },
            .Big => {
                bytes[0] = @intCast((value >> 8) & 0xFF);
                bytes[1] = @intCast(value & 0xFF);
            },
        }

        self.write(&bytes);
    }

    pub fn readUint24(self: *BinaryStream, endianess: ?Endianess) u24 {
        const bytes = self.read(3);
        if (bytes.len < 3) {
            Logger.ERROR("Cannot read uint24: not enough bytes", .{});
            return 0;
        }
        return switch (endianess orelse .Big) {
            .Little => @as(u24, @intCast(bytes[0])) | (@as(u24, @intCast(bytes[1])) << 8) | (@as(u24, @intCast(bytes[2])) << 16),
            .Big => (@as(u24, @intCast(bytes[0])) << 16) | (@as(u24, @intCast(bytes[1])) << 8) | @as(u24, @intCast(bytes[2])),
        };
    }

    pub fn writeUint24(self: *BinaryStream, value: u24, endianess: ?Endianess) void {
        var bytes: [3]u8 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bytes[0] = @intCast(value & 0xFF);
                bytes[1] = @intCast((value >> 8) & 0xFF);
                bytes[2] = @intCast((value >> 16) & 0xFF);
            },
            .Big => {
                bytes[0] = @intCast((value >> 16) & 0xFF);
                bytes[1] = @intCast((value >> 8) & 0xFF);
                bytes[2] = @intCast(value & 0xFF);
            },
        }

        self.write(&bytes);
    }

    pub fn readUint32(self: *BinaryStream, endianess: ?Endianess) u32 {
        const bytes = self.read(4);
        if (bytes.len < 4) {
            Logger.ERROR("Cannot read uint32: not enough bytes", .{});
            return 0;
        }
        return switch (endianess orelse .Big) {
            .Little => @as(u32, @intCast(bytes[0])) | (@as(u32, @intCast(bytes[1])) << 8) | (@as(u32, @intCast(bytes[2])) << 16) | (@as(u32, @intCast(bytes[3])) << 24),
            .Big => (@as(u32, @intCast(bytes[0])) << 24) | (@as(u32, @intCast(bytes[1])) << 16) | (@as(u32, @intCast(bytes[2])) << 8) | @as(u32, @intCast(bytes[3])),
        };
    }

    pub fn writeUint32(self: *BinaryStream, value: u32, endianess: ?Endianess) void {
        var bytes: [4]u8 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bytes[0] = @intCast(value & 0xFF);
                bytes[1] = @intCast((value >> 8) & 0xFF);
                bytes[2] = @intCast((value >> 16) & 0xFF);
                bytes[3] = @intCast((value >> 24) & 0xFF);
            },
            .Big => {
                bytes[0] = @intCast((value >> 24) & 0xFF);
                bytes[1] = @intCast((value >> 16) & 0xFF);
                bytes[2] = @intCast((value >> 8) & 0xFF);
                bytes[3] = @intCast(value & 0xFF);
            },
        }
        self.write(&bytes);
    }

    pub fn readUint64(self: *BinaryStream, endianess: ?Endianess) u64 {
        const bytes = self.read(8);
        if (bytes.len < 8) {
            Logger.ERROR("Cannot read uint64: not enough bytes", .{});
            return 0;
        }
        return switch (endianess orelse .Big) {
            .Little => @as(u64, @intCast(bytes[0])) | (@as(u64, @intCast(bytes[1])) << 8) | (@as(u64, @intCast(bytes[2])) << 16) | (@as(u64, @intCast(bytes[3])) << 24) | (@as(u64, @intCast(bytes[4])) << 32) | (@as(u64, @intCast(bytes[5])) << 40) | (@as(u64, @intCast(bytes[6])) << 48) | (@as(u64, @intCast(bytes[7])) << 56),
            .Big => (@as(u64, @intCast(bytes[0])) << 56) | (@as(u64, @intCast(bytes[1])) << 48) | (@as(u64, @intCast(bytes[2])) << 40) | (@as(u64, @intCast(bytes[3])) << 32) | (@as(u64, @intCast(bytes[4])) << 24) | (@as(u64, @intCast(bytes[5])) << 16) | (@as(u64, @intCast(bytes[6])) << 8) | @as(u64, @intCast(bytes[7])),
        };
    }

    pub fn writeUint64(self: *BinaryStream, value: u64, endianess: ?Endianess) void {
        var bytes: [8]u8 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bytes[0] = @intCast(value & 0xFF);
                bytes[1] = @intCast((value >> 8) & 0xFF);
                bytes[2] = @intCast((value >> 16) & 0xFF);
                bytes[3] = @intCast((value >> 24) & 0xFF);
                bytes[4] = @intCast((value >> 32) & 0xFF);
                bytes[5] = @intCast((value >> 40) & 0xFF);
                bytes[6] = @intCast((value >> 48) & 0xFF);
                bytes[7] = @intCast((value >> 56) & 0xFF);
            },
            .Big => {
                bytes[0] = @intCast((value >> 56) & 0xFF);
                bytes[1] = @intCast((value >> 48) & 0xFF);
                bytes[2] = @intCast((value >> 40) & 0xFF);
                bytes[3] = @intCast((value >> 32) & 0xFF);
                bytes[4] = @intCast((value >> 24) & 0xFF);
                bytes[5] = @intCast((value >> 16) & 0xFF);
                bytes[6] = @intCast((value >> 8) & 0xFF);
                bytes[7] = @intCast(value & 0xFF);
            },
        }
        self.write(&bytes);
    }

    pub fn readInt8(self: *BinaryStream) i8 {
        return @intCast(self.readUint8());
    }

    pub fn writeInt8(self: *BinaryStream, value: i8) void {
        self.writeUint8(@intCast(value));
    }

    pub fn readInt16(self: *BinaryStream, endianess: ?Endianess) i16 {
        const bytes = self.read(2);
        if (bytes.len < 2) {
            Logger.ERROR("Cannot read int16: not enough bytes", .{});
            return 0;
        }
        return switch (endianess orelse .Big) {
            .Little => @as(i16, @intCast(bytes[0])) | (@as(i16, @intCast(bytes[1])) << 8),
            .Big => (@as(i16, @intCast(bytes[0])) << 8) | @as(i16, @intCast(bytes[1])),
        };
    }

    pub fn writeInt16(self: *BinaryStream, value: i16, endianess: ?Endianess) void {
        switch (endianess orelse .Big) {
            .Little => {
                self.writeUint8(@intCast(value & 0xFF));
                self.writeUint8(@intCast((value >> 8) & 0xFF));
            },
            .Big => {
                self.writeUint8(@intCast((value >> 8) & 0xFF));
                self.writeUint8(@intCast(value & 0xFF));
            },
        }
    }

    pub fn readInt32(self: *BinaryStream, endianess: ?Endianess) i32 {
        const bytes = self.read(4);
        if (bytes.len < 4) {
            Logger.ERROR("Cannot read int32: not enough bytes", .{});
            return 0;
        }
        return switch (endianess orelse .Big) {
            .Little => @as(i32, @intCast(bytes[0])) | (@as(i32, @intCast(bytes[1])) << 8) | (@as(i32, @intCast(bytes[2])) << 16) | (@as(i32, @intCast(bytes[3])) << 24),
            .Big => (@as(i32, @intCast(bytes[0])) << 24) | (@as(i32, @intCast(bytes[1])) << 16) | (@as(i32, @intCast(bytes[2])) << 8) | @as(i32, @intCast(bytes[3])),
        };
    }

    pub fn writeInt32(self: *BinaryStream, value: i32, endianess: ?Endianess) void {
        switch (endianess orelse .Big) {
            .Little => {
                self.writeUint8(@intCast(value & 0xFF));
                self.writeUint8(@intCast((value >> 8) & 0xFF));
                self.writeUint8(@intCast((value >> 16) & 0xFF));
                self.writeUint8(@intCast((value >> 24) & 0xFF));
            },
            .Big => {
                self.writeUint8(@intCast((value >> 24) & 0xFF));
                self.writeUint8(@intCast((value >> 16) & 0xFF));
                self.writeUint8(@intCast((value >> 8) & 0xFF));
                self.writeUint8(@intCast(value & 0xFF));
            },
        }
    }

    pub fn readInt64(self: *BinaryStream, endianess: ?Endianess) i64 {
        const bytes = self.read(8);
        if (bytes.len < 8) {
            Logger.ERROR("Cannot read int64: not enough bytes", .{});
            return 0;
        }
        return switch (endianess orelse .Big) {
            .Little => @as(i64, @intCast(bytes[0])) | (@as(i64, @intCast(bytes[1])) << 8) | (@as(i64, @intCast(bytes[2])) << 16) | (@as(i64, @intCast(bytes[3])) << 24) | (@as(i64, @intCast(bytes[4])) << 32) | (@as(i64, @intCast(bytes[5])) << 40) | (@as(i64, @intCast(bytes[6])) << 48) | (@as(i64, @intCast(bytes[7])) << 56),
            .Big => (@as(i64, @intCast(bytes[0])) << 56) | (@as(i64, @intCast(bytes[1])) << 48) | (@as(i64, @intCast(bytes[2])) << 40) | (@as(i64, @intCast(bytes[3])) << 32) | (@as(i64, @intCast(bytes[4])) << 24) | (@as(i64, @intCast(bytes[5])) << 16) | (@as(i64, @intCast(bytes[6])) << 8) | @as(i64, @intCast(bytes[7])),
        };
    }

    pub fn writeInt64(self: *BinaryStream, value: i64, endianess: ?Endianess) void {
        switch (endianess orelse .Big) {
            .Little => {
                self.writeUint8(@intCast(value & 0xFF));
                self.writeUint8(@intCast((value >> 8) & 0xFF));
                self.writeUint8(@intCast((value >> 16) & 0xFF));
                self.writeUint8(@intCast((value >> 24) & 0xFF));
                self.writeUint8(@intCast((value >> 32) & 0xFF));
                self.writeUint8(@intCast((value >> 40) & 0xFF));
                self.writeUint8(@intCast((value >> 48) & 0xFF));
                self.writeUint8(@intCast((value >> 56) & 0xFF));
            },
            .Big => {
                self.writeUint8(@intCast((value >> 56) & 0xFF));
                self.writeUint8(@intCast((value >> 48) & 0xFF));
                self.writeUint8(@intCast((value >> 40) & 0xFF));
                self.writeUint8(@intCast((value >> 32) & 0xFF));
                self.writeUint8(@intCast((value >> 24) & 0xFF));
                self.writeUint8(@intCast((value >> 16) & 0xFF));
                self.writeUint8(@intCast((value >> 8) & 0xFF));
                self.writeUint8(@intCast(value & 0xFF));
            },
        }
    }

    pub fn readBool(self: *BinaryStream) bool {
        return self.readUint8() != 0;
    }

    pub fn writeBool(self: *BinaryStream, value: bool) void {
        self.writeUint8(if (value) 1 else 0);
    }

    pub fn readFloat32(self: *BinaryStream, endianess: ?Endianess) f32 {
        const bytes = self.read(4);
        if (bytes.len < 4) {
            Logger.ERROR("Cannot read float32: not enough bytes", .{});
            return 0;
        }
        var bits: u32 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bits = @as(u32, bytes[0]) |
                    (@as(u32, bytes[1]) << 8) |
                    (@as(u32, bytes[2]) << 16) |
                    (@as(u32, bytes[3]) << 24);
            },
            .Big => {
                bits = (@as(u32, bytes[0]) << 24) |
                    (@as(u32, bytes[1]) << 16) |
                    (@as(u32, bytes[2]) << 8) |
                    @as(u32, bytes[3]);
            },
        }

        return @bitCast(bits);
    }

    pub fn writeFloat32(self: *BinaryStream, value: f32, endianess: ?Endianess) void {
        const bits: u32 = @bitCast(value);
        var bytes: [4]u8 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bytes[0] = @intCast(bits & 0xFF);
                bytes[1] = @intCast((bits >> 8) & 0xFF);
                bytes[2] = @intCast((bits >> 16) & 0xFF);
                bytes[3] = @intCast((bits >> 24) & 0xFF);
            },
            .Big => {
                bytes[0] = @intCast((bits >> 24) & 0xFF);
                bytes[1] = @intCast((bits >> 16) & 0xFF);
                bytes[2] = @intCast((bits >> 8) & 0xFF);
                bytes[3] = @intCast(bits & 0xFF);
            },
        }

        self.write(&bytes);
    }

    pub fn readFloat64(self: *BinaryStream, endianess: ?Endianess) f64 {
        const bytes = self.read(8);
        if (bytes.len < 8) {
            Logger.ERROR("Cannot read float64: not enough bytes", .{});
            return 0;
        }
        var bits: u64 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bits = @as(u64, bytes[0]) |
                    (@as(u64, bytes[1]) << 8) |
                    (@as(u64, bytes[2]) << 16) |
                    (@as(u64, bytes[3]) << 24) |
                    (@as(u64, bytes[4]) << 32) |
                    (@as(u64, bytes[5]) << 40) |
                    (@as(u64, bytes[6]) << 48) |
                    (@as(u64, bytes[7]) << 56);
            },
            .Big => {
                bits = (@as(u64, bytes[0]) << 56) |
                    (@as(u64, bytes[1]) << 48) |
                    (@as(u64, bytes[2]) << 40) |
                    (@as(u64, bytes[3]) << 32) |
                    (@as(u64, bytes[4]) << 24) |
                    (@as(u64, bytes[5]) << 16) |
                    (@as(u64, bytes[6]) << 8) |
                    @as(u64, bytes[7]);
            },
        }

        return @bitCast(bits);
    }

    pub fn writeFloat64(self: *BinaryStream, value: f64, endianess: ?Endianess) void {
        const bits: u64 = @bitCast(value);
        var bytes: [8]u8 = undefined;

        switch (endianess orelse .Big) {
            .Little => {
                bytes[0] = @intCast(bits & 0xFF);
                bytes[1] = @intCast((bits >> 8) & 0xFF);
                bytes[2] = @intCast((bits >> 16) & 0xFF);
                bytes[3] = @intCast((bits >> 24) & 0xFF);
                bytes[4] = @intCast((bits >> 32) & 0xFF);
                bytes[5] = @intCast((bits >> 40) & 0xFF);
                bytes[6] = @intCast((bits >> 48) & 0xFF);
                bytes[7] = @intCast((bits >> 56) & 0xFF);
            },
            .Big => {
                bytes[0] = @intCast((bits >> 56) & 0xFF);
                bytes[1] = @intCast((bits >> 48) & 0xFF);
                bytes[2] = @intCast((bits >> 40) & 0xFF);
                bytes[3] = @intCast((bits >> 32) & 0xFF);
                bytes[4] = @intCast((bits >> 24) & 0xFF);
                bytes[5] = @intCast((bits >> 16) & 0xFF);
                bytes[6] = @intCast((bits >> 8) & 0xFF);
                bytes[7] = @intCast(bits & 0xFF);
            },
        }

        self.write(&bytes);
    }

    pub fn readString16(self: *BinaryStream, endianess: ?Endianess) []const u8 {
        const length = self.readUint16(endianess);
        return self.read(length);
    }

    pub fn writeString16(self: *BinaryStream, value: []const u8, endianess: ?Endianess) void {
        self.writeUint16(@as(u16, @intCast(value.len)), endianess);
        self.write(value);
    }

    pub fn readString32(self: *BinaryStream, endianess: ?Endianess) []const u8 {
        const length = self.readUint32(endianess);
        return self.read(length);
    }

    pub fn writeString32(self: *BinaryStream, value: []const u8, endianess: ?Endianess) void {
        self.writeUint32(@as(u32, @intCast(value.len)), endianess);
        self.write(value);
    }

    pub fn readVarInt(self: *BinaryStream, _: ?Endianess) u32 {
        var value: u32 = 0;
        var size: u3 = 0;

        while (true) {
            const current_byte = self.readUint8();
            const shift_amount: u5 = switch (size) {
                0 => 0,
                1 => 7,
                2 => 14,
                3 => 21,
                4 => 28,
                else => {
                    Logger.ERROR("VarInt is too big", .{});
                    return 0;
                },
            };

            value |= @as(u32, current_byte & 0x7F) << shift_amount;
            size +%= 1;
            if (size > 5) {
                Logger.ERROR("VarInt is too big", .{});
                return 0;
            }
            if (current_byte & 0x80 != 0x80) break;
        }

        return value;
    }

    pub fn writeVarInt(self: *BinaryStream, mut_value: u32, _: ?Endianess) void {
        var value = mut_value;

        while (true) {
            var byte: u8 = @intCast(value & 0x7F);
            value >>= 7;

            if (value != 0) {
                byte |= 0x80;
            }

            self.writeUint8(byte);

            if (value == 0) {
                break;
            }
        }
    }

    pub fn readVarString(self: *BinaryStream) []const u8 {
        const length = self.readVarInt(.Big);
        return self.read(length);
    }

    pub fn writeVarString(self: *BinaryStream, value: []const u8) void {
        self.writeVarInt(@as(u32, @intCast(value.len)), .Big);
        self.write(value);
    }

    pub fn readVarLong(self: *BinaryStream, _: ?Endianess) u64 {
        var value: u64 = 0;
        var size: u4 = 0;

        while (true) {
            const current_byte = self.readUint8();
            const shift_amount: u6 = switch (size) {
                0 => 0,
                1 => 7,
                2 => 14,
                3 => 21,
                4 => 28,
                5 => 35,
                6 => 42,
                7 => 49,
                8 => 56,
                9 => 63,
                else => {
                    Logger.ERROR("VarLong is too big", .{});
                    return 0;
                },
            };

            value |= @as(u64, current_byte & 0x7F) << shift_amount;
            size +%= 1;
            if (size > 10) {
                Logger.ERROR("VarLong is too big", .{});
                return 0;
            }
            if (current_byte & 0x80 != 0x80) break;
        }

        return value;
    }

    pub fn writeVarLong(self: *BinaryStream, mut_value: u64, _: ?Endianess) void {
        var value = mut_value;

        while (true) {
            var byte: u8 = @intCast(value & 0x7F);
            value >>= 7;

            if (value != 0) {
                byte |= 0x80;
            }

            self.writeUint8(byte);

            if (value == 0) {
                break;
            }
        }
    }

    pub fn readZigZong(self: *BinaryStream) i64 {
        const value = self.readVarLong(null);
        return @as(i64, @bitCast(value >> 1)) ^ (-@as(i64, @intCast(value & 1)));
    }

    pub fn writeZigZong(self: *BinaryStream, value: i64) void {
        const encoded = @as(u64, @bitCast((value << 1) ^ (value >> 63)));
        self.writeVarLong(encoded, null);
    }

    pub fn readZigZag(self: *BinaryStream) i32 {
        const value = self.readVarInt(null);
        return @as(i32, @intCast(value >> 1)) ^ (-@as(i32, @intCast(value & 1)));
    }

    pub fn writeZigZag(self: *BinaryStream, value: i32) void {
        const encoded = @as(u32, @intCast((value << 1) ^ (value >> 31)));
        self.writeVarInt(encoded, null);
    }

    pub fn readUUID(self: *BinaryStream) []const u8 {
        const bytes_m = self.read(8);
        const bytes_l = self.read(8);
        if ((bytes_m.len < 8) || (bytes_l.len < 8)) {
            Logger.ERROR("Cannot read UUID: not enough bytes", .{});
            return "";
        }

        // Create a buffer for the UUID string (36 chars: 32 hex digits + 4 hyphens)
        var uuid_buffer = self.allocator.alloc(u8, 36) catch |err| {
            Logger.ERROR("Failed to allocate memory for UUID: {}", .{err});
            return "";
        };

        // Process first 8 bytes (most significant)
        var i: usize = 0;
        for (bytes_m, 0..) |byte, index| {
            // Format each byte as hex
            const hex_chars = "0123456789abcdef";
            uuid_buffer[i] = hex_chars[(byte >> 4) & 0xF];
            uuid_buffer[i + 1] = hex_chars[byte & 0xF];
            i += 2;

            // Insert hyphens after positions 8 and 13 (after 4th and 6th byte)
            if (index == 3 or index == 5) {
                uuid_buffer[i] = '-';
                i += 1;
            }
        }

        // Process last 8 bytes (least significant)
        // Insert hyphen before the 9th byte
        uuid_buffer[i] = '-';
        i += 1;

        for (bytes_l, 0..) |byte, index| {
            // Format each byte as hex
            const hex_chars = "0123456789abcdef";
            uuid_buffer[i] = hex_chars[(byte >> 4) & 0xF];
            uuid_buffer[i + 1] = hex_chars[byte & 0xF];
            i += 2;

            // Insert hyphen after position 23 (after 11th byte)
            if (index == 1) {
                uuid_buffer[i] = '-';
                i += 1;
            }
        }

        return uuid_buffer;
    }

    pub fn writeUUID(self: *BinaryStream, value: []const u8) void {
        if (value.len != 36) {
            Logger.ERROR("Invalid UUID format: incorrect length", .{});
            return;
        }

        // Remove hyphens and convert to bytes
        var bytes_m: [8]u8 = undefined;
        var bytes_l: [8]u8 = undefined;

        var i: usize = 0;
        var j: usize = 0;

        // Process first 8 bytes
        while (j < 8) {
            if (value[i] == '-') {
                i += 1;
                continue;
            }

            const high = switch (value[i]) {
                '0'...'9' => value[i] - '0',
                'a'...'f' => value[i] - 'a' + 10,
                'A'...'F' => value[i] - 'A' + 10,
                else => {
                    Logger.ERROR("Invalid UUID format: invalid character", .{});
                    return;
                },
            };

            if (i + 1 >= value.len) {
                Logger.ERROR("Invalid UUID format: unexpected end", .{});
                return;
            }

            const low = switch (value[i + 1]) {
                '0'...'9' => value[i + 1] - '0',
                'a'...'f' => value[i + 1] - 'a' + 10,
                'A'...'F' => value[i + 1] - 'A' + 10,
                else => {
                    Logger.ERROR("Invalid UUID format: invalid character", .{});
                    return;
                },
            };

            bytes_m[j] = @as(u8, @intCast(high << 4 | low));
            j += 1;
            i += 2;
        }

        // Skip any remaining hyphens between the two parts
        while (i < value.len and j == 8) {
            if (value[i] == '-') {
                i += 1;
            } else {
                break;
            }
        }

        // Process last 8 bytes
        j = 0;
        while (j < 8 and i < value.len) {
            if (value[i] == '-') {
                i += 1;
                continue;
            }

            if (i + 1 >= value.len) {
                Logger.ERROR("Invalid UUID format: unexpected end", .{});
                return;
            }

            const high = switch (value[i]) {
                '0'...'9' => value[i] - '0',
                'a'...'f' => value[i] - 'a' + 10,
                'A'...'F' => value[i] - 'A' + 10,
                else => {
                    Logger.ERROR("Invalid UUID format: invalid character", .{});
                    return;
                },
            };

            const low = switch (value[i + 1]) {
                '0'...'9' => value[i + 1] - '0',
                'a'...'f' => value[i + 1] - 'a' + 10,
                'A'...'F' => value[i + 1] - 'A' + 10,
                else => {
                    Logger.ERROR("Invalid UUID format: invalid character", .{});
                    return;
                },
            };

            bytes_l[j] = @as(u8, @intCast(high << 4 | low));
            j += 1;
            i += 2;
        }

        // Write the bytes to the stream
        self.write(&bytes_m);
        self.write(&bytes_l);
    }

    pub fn readComptime(self: *BinaryStream, comptime T: type) !T {
        if (self.position + @sizeOf(T) > self.buffer.items.len) {
            return error.OutOfBounds;
        }
        const bytes = self.read(@sizeOf(T));
        return std.mem.bytesToValue(T, bytes);
    }

    pub fn writeMagic(self: *BinaryStream) void {
        self.write(&MagicBytes);
    }

    pub fn readMagic(self: *BinaryStream) []const u8 {
        return self.read(16);
    }
};

// Factory function for creating a stream from a buffer and optional position
pub fn init(buffer: []const u8, position: ?usize) BinaryStream {
    const pos = position orelse 0; // Default position to 0 if null
    return BinaryStream.init(Callocator.get(), buffer, pos);
}
