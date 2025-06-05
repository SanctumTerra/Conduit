const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;
const CAllocator = @import("CAllocator");

pub const Login = struct {
    protocol: i32,
    client: []const u8,
    identity: []const u8,

    pub fn init(protocol: i32, client: []const u8, identity: []const u8) Login {
        return Login{
            .protocol = protocol,
            .client = client,
            .identity = identity,
        };
    }

    pub fn serialize(self: *Login) []u8 {
        var stream = BinaryStream.initEmpty();
        stream.writeVarInt(Packets.Login, .Big);
        stream.writeInt32(self.protocol, .Big);
        stream.writeVarInt(@as(u32, @intCast(self.client.len)) + @as(u32, @intCast(self.identity.len)) + 8, .Big);
        stream.writeString32(self.client, .Little);
        stream.writeString32(self.identity, .Little);
        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize login packet: {s}", .{@errorName(err)});
            return &[_]u8{};
        };
    }

    pub fn deserialize(data: []const u8) Login {
        var stream = BinaryStream.init(data, 0);
        _ = stream.readVarInt(.Big);
        const protocol = stream.readInt32(.Big);
        _ = stream.readVarInt(.Big);
        const identity = stream.readString32(.Little);
        const client = stream.readString32(.Little);

        const client_dup = CAllocator.get().alloc(u8, client.len) catch |err| {
            Logger.ERROR("Failed to allocate memory for client data: {any}", .{err});
            return .{ .protocol = protocol, .client = &[_]u8{}, .identity = &[_]u8{} };
        };
        @memcpy(client_dup, client);

        const identity_dup = CAllocator.get().alloc(u8, identity.len) catch |err| {
            Logger.ERROR("Failed to allocate memory for identity data: {any}", .{err});
            return .{ .protocol = protocol, .client = &[_]u8{}, .identity = &[_]u8{} };
        };
        @memcpy(identity_dup, identity);
        return Login.init(protocol, client_dup, identity_dup);
    }
};
