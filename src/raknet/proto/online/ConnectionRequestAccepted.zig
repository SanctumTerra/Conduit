const CAllocator = @import("CAllocator");
const BinaryStream = @import("BinaryStream");
const Packets = @import("../Packets.zig").Packets;
const Logger = @import("Logger").Logger;
const Address = @import("../Address.zig").Address;

pub const ConnectionRequestAccepted = struct {
    address: Address,
    system_index: u16,
    /// System Address that will be written 10 times.
    addresses: Address, // Only the first of the 10 deserialized addresses is stored here.
    request_timestamp: i64,
    timestamp: i64,

    pub fn init(address: Address, system_index: u16, addresses: Address, request_timestamp: i64, timestamp: i64) ConnectionRequestAccepted {
        return .{
            .address = address,
            .system_index = system_index,
            .addresses = addresses,
            .request_timestamp = request_timestamp,
            .timestamp = timestamp,
        };
    }

    pub fn serialize(self: *const ConnectionRequestAccepted) []const u8 {
        const buffer = &[_]u8{};
        var stream = BinaryStream.init(buffer, 0);
        defer stream.deinit();

        stream.writeVarInt(Packets.ConnectionRequestAccepted, .Big);

        const address_buffer = self.address.write(CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize client address: {}", .{err});
            return &[_]u8{};
        };
        defer CAllocator.get().free(address_buffer);
        stream.write(address_buffer);

        stream.writeUint16(self.system_index, .Big);

        const internal_address_buffer = self.addresses.write(CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to serialize internal system address: {}", .{err});
            return &[_]u8{};
        };
        defer CAllocator.get().free(internal_address_buffer);

        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            stream.write(internal_address_buffer);
        }

        stream.writeInt64(self.request_timestamp, .Big);
        stream.writeInt64(self.timestamp, .Big);

        return stream.toOwnedSlice() catch |err| {
            Logger.ERROR("Failed to serialize ConnectionRequestAccepted: {}", .{err});
            return &[_]u8{};
        };
    }

    /// DEALLOCATE THE RETURNED ADDRESS AND THE NESTED .addresses FIELD AFTER USE
    pub fn deserialize(data: []const u8) !ConnectionRequestAccepted {
        var stream = BinaryStream.init(data, 0);
        defer stream.deinit();

        _ = stream.readVarInt(.Big); // Skip Packet ID

        const client_address = Address.read(&stream, CAllocator.get()) catch |err| {
            Logger.ERROR("Failed to deserialize client address: {}", .{err});
            return err;
        };

        const system_idx = stream.readUint16(.Big);

        var system_addresses_array: [10]Address = undefined;
        var first_system_address: Address = undefined;

        // Read 10 system addresses
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            system_addresses_array[i] = Address.read(&stream, CAllocator.get()) catch |err| {
                Logger.ERROR("Failed to deserialize system address index {}: {}", .{ i, err });
                // Deallocate successfully deserialized addresses before this one
                var k: u8 = 0;
                while (k < i) : (k += 1) {
                    system_addresses_array[k].deinit(CAllocator.get());
                }
                client_address.deinit(CAllocator.get()); // also deallocate the client_address
                return err;
            };
            if (i == 0) {
                first_system_address = system_addresses_array[0];
            }
        }

        // Deallocate the 9 system addresses that are not returned
        i = 1; // Start from the second address
        while (i < 10) : (i += 1) {
            system_addresses_array[i].deinit(CAllocator.get());
        }

        const req_timestamp = stream.readInt64(.Big);
        const server_timestamp = stream.readInt64(.Big);

        return ConnectionRequestAccepted.init(
            client_address,
            system_idx,
            first_system_address, // Only the first address is kept as per the original logic
            req_timestamp,
            server_timestamp,
        );
    }
};
