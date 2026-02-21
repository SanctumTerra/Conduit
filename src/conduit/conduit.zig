const std = @import("std");
const Events = @import("events/root.zig");
const Raknet = @import("Raknet");
const NetworkHandler = @import("./network/root.zig").NetworkHandler;
const Player = @import("./player/player.zig").Player;
const World = @import("./world/world.zig").World;
const Generator = @import("./world/generator/root.zig");

const loadBlockPermutations = @import("./world/block/root.zig").loadBlockPermutations;
const initRegistries = @import("./world/block/root.zig").initRegistries;
const deinitRegistries = @import("./world/block/root.zig").deinitRegistries;

pub const Conduit = struct {
    allocator: std.mem.Allocator,
    events: Events.Events,
    raknet: Raknet.Server,
    network: *NetworkHandler,
    players: std.AutoHashMap(i64, *Player),
    worlds: std.StringHashMap(*World),

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
            .players = std.AutoHashMap(i64, *Player).init(allocator),
            .worlds = std.StringHashMap(*World).init(allocator),
            .network = undefined,
        };
    }

    pub fn start(self: *Conduit) !void {
        try initRegistries(self.allocator);
        const count = try loadBlockPermutations(self.allocator);
        Raknet.Logger.INFO("Loaded {d} block permutations", .{count});

        const props = Generator.GeneratorProperties.init(null, .Overworld);
        const superflat = try Generator.SuperflatGenerator.init(self.allocator, props);
        const threaded = try Generator.ThreadedGenerator.init(self.allocator, superflat.asGenerator(), null);

        var world = try self.createWorld("world");
        _ = try world.createDimension("overworld", .Overworld, threaded);

        self.network = try NetworkHandler.init(self);
        var event = Events.types.ServerStartEvent{};
        _ = self.events.emit(Events.Event.ServerStart, &event);

        try self.raknet.start();
    }

    pub fn stop(self: *Conduit) !void {
        var event = Events.types.ServerShutdownEvent{};
        _ = self.events.emit(.ServerShutdown, &event);
    }

    pub fn getPlayerByConnection(self: *Conduit, connection: *Raknet.Connection) ?*Player {
        var it = self.players.valueIterator();
        while (it.next()) |player| {
            if (player.*.connection == connection) return player.*;
        }
        return null;
    }

    pub fn createWorld(self: *Conduit, identifier: []const u8) !*World {
        if (self.worlds.get(identifier)) |existing| return existing;

        const world = try self.allocator.create(World);
        world.* = try World.init(self, self.allocator, identifier, null);
        try self.worlds.put(identifier, world);
        return world;
    }

    pub fn getWorld(self: *Conduit, identifier: []const u8) ?*World {
        return self.worlds.get(identifier);
    }

    pub fn deinit(self: *Conduit) void {
        deinitRegistries();

        var it = self.players.valueIterator();
        while (it.next()) |player| {
            player.*.deinit();
            self.allocator.destroy(player.*);
        }
        self.players.deinit();

        var worlds_it = self.worlds.valueIterator();
        while (worlds_it.next()) |world| {
            world.*.deinit();
            self.allocator.destroy(world.*);
        }
        self.worlds.deinit();

        self.events.deinit();
        self.network.deinit();
        self.raknet.deinit();
    }
};
