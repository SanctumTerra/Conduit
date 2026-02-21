const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handleResourcePack(
    network: *NetworkHandler,
    connection: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const response = try Protocol.ResourcePackResponsePacket.deserialize(stream);
    Raknet.Logger.INFO("PACKET {any}", .{response});

    switch (response.response) {
        .HaveAllPacks => {
            var str = BinaryStream.init(network.allocator, null, null);
            defer str.deinit();

            const empty_packs = [_]Protocol.ResourceIdVersions{};
            const empty_experiments = [_]Protocol.Experiments{};

            var stack = Protocol.ResourcePackStackPacket{
                .mustAccept = false,
                .texturePacks = &empty_packs,
                .gameVersion = "26.0",
                .experiments = &empty_experiments,
                .experimentsPreviouslyToggled = false,
                .hasEditorPacks = false,
            };

            const serialized = try stack.serialize(&str);
            try network.sendPacket(connection, serialized);
        },
        .None => {
            Raknet.Logger.DEBUG("Unhandled ResourcePackClientResponse: None", .{});
        },
        .Refused => {
            if (network.conduit.getPlayerByConnection(connection)) |player| {
                try player.disconnect();
            }
        },
        .SendPacks => {},

        .Completed => {},
    }
}
