const std = @import("std");
const Events = @import("events/root.zig");
const BinaryStream = @import("BinaryStream").BinaryStream;
const Raknet = @import("Raknet");
const Protocol = @import("protocol");
const NetworkHandler = @import("./network/root.zig").NetworkHandler;
const Player = @import("./player/player.zig").Player;
const World = @import("./world/world.zig").World;
const Generator = @import("./world/generator/root.zig");
const ServerProperties = @import("./config.zig").ServerProperties;
const EntityType = @import("./entity/entity-type.zig").EntityType;

const loadBlockPermutations = @import("./world/block/root.zig").loadBlockPermutations;
const initRegistries = @import("./world/block/root.zig").initRegistries;
const deinitRegistries = @import("./world/block/root.zig").deinitRegistries;

const ItemPalette = @import("./items/item-palette.zig");
const CreativeContentLoader = @import("./items/creative-content-loader.zig");

pub const Conduit = struct {
    allocator: std.mem.Allocator,
    config: ServerProperties,
    events: Events.Events,
    raknet: Raknet.Server,
    network: *NetworkHandler,
    players: std.AutoHashMap(i64, *Player),
    connection_map: std.AutoHashMap(usize, *Player),
    players_mutex: std.Thread.Mutex,
    snapshot_buf: std.ArrayList(*Player),
    worlds: std.StringHashMap(*World),
    player_entity_type: EntityType,
    creative_content: ?CreativeContentLoader.CreativeContentData,

    pub fn init(allocator: std.mem.Allocator) !Conduit {
        const config = try ServerProperties.load(allocator, "server.properties");
        return Conduit{
            .allocator = allocator,
            .config = config,
            .events = Events.Events.init(allocator),
            .raknet = try Raknet.Server.init(.{
                .address = config.address,
                .port = config.port,
                .tick_rate = @intCast(config.max_tps),
                .allocator = allocator,
                .advertisement = .{
                    .game_type = .MCPE,
                    .level_name = config.motd,
                    .protocol = Protocol.PROTOCOL,
                    .version = "26.1",
                    .player_count = 0,
                    .max_players = @intCast(config.max_players),
                    .guid = 0,
                    .name = config.motd,
                    .gamemode = "Survival",
                },
            }),
            .players = std.AutoHashMap(i64, *Player).init(allocator),
            .connection_map = std.AutoHashMap(usize, *Player).init(allocator),
            .players_mutex = std.Thread.Mutex{},
            .snapshot_buf = std.ArrayList(*Player){ .items = &.{}, .capacity = 0 },
            .worlds = std.StringHashMap(*World).init(allocator),
            .player_entity_type = EntityType.init("minecraft:player", 1, &.{}, &.{}),
            .creative_content = null,
            .network = undefined,
        };
    }

    pub fn start(self: *Conduit) !void {
        try initRegistries(self.allocator);
        const count = try loadBlockPermutations(self.allocator);
        Raknet.Logger.INFO("Loaded {d} block permutations", .{count});

        try ItemPalette.initRegistry(self.allocator);
        const item_count = try ItemPalette.loadItemTypes(self.allocator);
        Raknet.Logger.INFO("Loaded {d} item types", .{item_count});

        self.creative_content = CreativeContentLoader.loadCreativeContent(self.allocator) catch |err| blk: {
            Raknet.Logger.ERROR("Failed to load creative content: {any}", .{err});
            break :blk null;
        };
        if (self.creative_content) |cc| {
            Raknet.Logger.INFO("Loaded {d} creative groups and {d} creative items", .{ cc.group_count, cc.item_count });
        }

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

        var it = self.players.valueIterator();
        while (it.next()) |player_ptr| {
            const player = player_ptr.*;
            var str = BinaryStream.init(self.allocator, null, null);
            defer str.deinit();
            var disconnect = Protocol.DisconnectPacket{
                .hideScreen = false,
                .reason = .Disconnected,
                .message = "Server shutdown.",
                .filtered = "Server shutdown.",
            };
            const serialized = try disconnect.serialize(&str);
            try self.network.sendImmediate(player.connection, serialized);
            player.connection.active = false;
        }
    }

    pub fn getPlayerByConnection(self: *Conduit, connection: *Raknet.Connection) ?*Player {
        self.players_mutex.lock();
        defer self.players_mutex.unlock();
        if (self.connection_map.count() == 0) return null;
        return self.connection_map.get(@intFromPtr(connection));
    }

    pub fn addPlayer(self: *Conduit, player: *Player) !void {
        self.players_mutex.lock();
        defer self.players_mutex.unlock();
        try self.players.put(player.entity.runtime_id, player);
        try self.connection_map.put(@intFromPtr(player.connection), player);
        self.raknet.options.advertisement.player_count = @intCast(self.players.count());
    }

    pub fn removePlayer(self: *Conduit, player: *Player) void {
        self.players_mutex.lock();
        defer self.players_mutex.unlock();
        _ = self.players.remove(player.entity.runtime_id);
        _ = self.connection_map.remove(@intFromPtr(player.connection));
        self.raknet.options.advertisement.player_count = @intCast(self.players.count());
    }

    pub fn getPlayerSnapshots(self: *Conduit) []*Player {
        self.players_mutex.lock();
        defer self.players_mutex.unlock();
        self.snapshot_buf.clearRetainingCapacity();
        var it = self.players.valueIterator();
        while (it.next()) |p| {
            self.snapshot_buf.append(self.allocator, p.*) catch break;
        }
        return self.snapshot_buf.items;
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
        self.raknet.deinit();

        deinitRegistries();
        ItemPalette.deinitRegistry();
        if (self.creative_content) |*cc| cc.deinit();
        self.config.deinit();

        var it = self.players.valueIterator();
        while (it.next()) |player| {
            player.*.deinit();
            self.allocator.destroy(player.*);
        }
        self.players.deinit();
        self.connection_map.deinit();
        self.snapshot_buf.deinit(self.allocator);

        var worlds_it = self.worlds.valueIterator();
        while (worlds_it.next()) |world| {
            world.*.deinit();
            self.allocator.destroy(world.*);
        }
        self.worlds.deinit();

        self.events.deinit();
        self.network.deinit();
    }
};
