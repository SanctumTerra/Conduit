const std = @import("std");
const Events = @import("events/root.zig");
const Raknet = @import("Raknet");
const NetworkHandler = @import("./network/root.zig").NetworkHandler;

pub const Conduit = struct {
    allocator: std.mem.Allocator,
    events: Events.Events,
    raknet: Raknet.Server,
    network: *NetworkHandler,

    pub fn init(allocator: std.mem.Allocator) !Conduit {
        return Conduit{
            .allocator = allocator,
            .events = Events.Events.init(allocator),
            .raknet = try Raknet.Server.init(.{
                .address = "0.0.0.0",
                .port = 19132,
                .tick_rate = 50,
                .allocator = allocator,
            }),
            .network = undefined,
        };
    }

    pub fn start(self: *Conduit) !void {
        self.network = try NetworkHandler.init(self);
        var event = Events.types.ServerStartEvent{};
        _ = self.events.emit(Events.Event.ServerStart, &event);

        try self.raknet.start();
    }

    pub fn stop(self: *Conduit) !void {
        var event = Events.types.ServerShutdownEvent{};
        _ = self.events.emit(.ServerShutdown, &event);
    }

    pub fn deinit(self: *Conduit) void {
        self.events.deinit();
        self.network.deinit();
        self.raknet.deinit();
    }
};
