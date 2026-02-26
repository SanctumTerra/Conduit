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
const EntityTypeRegistry = @import("./entity/entity-type-registry.zig");
const Entity = @import("./entity/entity.zig").Entity;

const loadBlockPermutations = @import("./world/block/root.zig").loadBlockPermutations;
const initRegistries = @import("./world/block/root.zig").initRegistries;
const deinitRegistries = @import("./world/block/root.zig").deinitRegistries;
const ChestTrait = @import("./world/block/traits/chest.zig").ChestTrait;
const BarrelTrait = @import("./world/block/traits/barrel.zig").BarrelTrait;
const UpperBlockTrait = @import("./world/block/traits/upper-block.zig").UpperBlockTrait;
const OpenBitTrait = @import("./world/block/traits/open-bit.zig").OpenBitTrait;
const LevelDBProvider = @import("./world/provider/leveldb-provider.zig").LevelDBProvider;
const WorldProvider = @import("./world/provider/world-provider.zig").WorldProvider;

const ItemPalette = @import("./items/item-palette.zig");
const CreativeContentLoader = @import("./items/creative-content-loader.zig");
const TaskQueue = @import("./tasks.zig").TaskQueue;
const ThreadedTaskQueue = @import("./threaded-tasks.zig").ThreadedTaskQueue;

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
    tick_count: u64 = 0,
    work_time_accumulator: u64 = 0,
    tasks_time_accumulator: u64 = 0,
    current_tps: f64 = 20.0,
    tasks: TaskQueue,
    threaded_tasks: ThreadedTaskQueue,

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
                    .gamemode = "Creative",
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
            .tasks = TaskQueue.init(allocator),
            .threaded_tasks = ThreadedTaskQueue.init(allocator),
        };
    }

    pub fn start(self: *Conduit) !void {
        try initRegistries(self.allocator);
        // TODO: Implement registerTrait instead of trait.register()
        try ChestTrait.register();
        try BarrelTrait.register();
        try UpperBlockTrait.registerForState("upper_block_bit");
        try OpenBitTrait.registerForState("open_bit");
        const count = try loadBlockPermutations(self.allocator);
        Raknet.Logger.INFO("Loaded {d} block permutations", .{count});

        try ItemPalette.initRegistry(self.allocator);
        const item_count = try ItemPalette.loadItemTypes(self.allocator);
        Raknet.Logger.INFO("Loaded {d} item types", .{item_count});

        const entity_type_count = try EntityTypeRegistry.initRegistry(self.allocator);
        Raknet.Logger.INFO("Loaded {d} entity types", .{entity_type_count});

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

        std.fs.cwd().makePath("worlds/world/db") catch {};
        const leveldb_provider = try LevelDBProvider.init(self.allocator, "worlds/world/db");
        var world = try self.createWorld("world", leveldb_provider.asProvider());
        const dim = try world.createDimension("overworld", .Overworld, threaded);

        if (readLevelDatSpawn(self.allocator, "worlds/world/level.dat")) |spawn| {
            dim.spawn_position = spawn;
            Raknet.Logger.INFO("World spawn: {d}, {d}, {d}", .{ spawn.x, spawn.y, spawn.z });
        } else |_| {}

        self.network = try NetworkHandler.init(self);
        self.raknet.setTickCallback(onTick, self);
        try self.threaded_tasks.start();
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

    pub fn getEntityByRuntimeId(self: *Conduit, runtime_id: i64) ?*Entity {
        var worlds_it = self.worlds.valueIterator();
        while (worlds_it.next()) |world| {
            var dims_it = world.*.dimensions.valueIterator();
            while (dims_it.next()) |dim| {
                if (dim.*.getEntity(runtime_id)) |entity| return entity;
            }
        }
        return null;
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

    fn onTick(context: ?*anyopaque) void {
        const self = @as(*Conduit, @ptrCast(@alignCast(context)));
        const work_start = std.time.nanoTimestamp();
        const tick_budget_ns: u64 = std.time.ns_per_s / @as(u64, self.config.max_tps);

        self.tick_count += 1;

        const snapshots = self.getPlayerSnapshots();
        for (snapshots) |player| {
            if (!player.spawned) continue;
            player.entity.fireEvent(.Tick, .{&player.entity});
        }

        var worlds_it = self.worlds.valueIterator();
        while (worlds_it.next()) |world| {
            var dims_it = world.*.dimensions.valueIterator();
            while (dims_it.next()) |dim| {
                var ent_it = dim.*.entities.valueIterator();
                while (ent_it.next()) |entity| {
                    entity.*.fireEvent(.Tick, .{entity.*});
                }
            }
        }

        const tasks_start = std.time.nanoTimestamp();
        _ = self.tasks.runUntil(work_start, tick_budget_ns * 40 / 100);
        const tasks_ns: u64 = @intCast(@max(0, std.time.nanoTimestamp() - tasks_start));
        self.tasks_time_accumulator += tasks_ns;

        self.threaded_tasks.drainCompleted();

        const work_ns: u64 = @intCast(@max(0, std.time.nanoTimestamp() - work_start));
        self.work_time_accumulator += work_ns;

        if (self.tick_count % 20 == 0) {
            const avg_work_ns = self.work_time_accumulator / 20;
            const avg_tasks_ns = self.tasks_time_accumulator / 20;
            self.work_time_accumulator = 0;
            self.tasks_time_accumulator = 0;

            const avg_work_ms = @as(f64, @floatFromInt(avg_work_ns)) / 1_000_000.0;
            const avg_tasks_ms = @as(f64, @floatFromInt(avg_tasks_ns)) / 1_000_000.0;

            if (avg_work_ns >= tick_budget_ns) {
                const work_s: f64 = @as(f64, @floatFromInt(avg_work_ns)) / 1_000_000_000.0;
                self.current_tps = @min(20.0, 1.0 / work_s);
                Raknet.Logger.INFO("TPS: {d:.1} | tick: {d:.1}ms | tasks: {d:.1}ms | pending: {d}", .{
                    self.current_tps,
                    avg_work_ms,
                    avg_tasks_ms,
                    self.tasks.pending(),
                });
            } else {
                self.current_tps = 20.0;
            }
        }

        if (self.tick_count % 6000 == 0) {
            self.saveAllWorlds();
        }
    }

    pub fn createWorld(self: *Conduit, identifier: []const u8, provider: ?WorldProvider) !*World {
        if (self.worlds.get(identifier)) |existing| return existing;

        const world = try self.allocator.create(World);
        world.* = try World.init(self, self.allocator, identifier, provider);
        try self.worlds.put(identifier, world);
        return world;
    }

    pub fn getWorld(self: *Conduit, identifier: []const u8) ?*World {
        return self.worlds.get(identifier);
    }

    pub fn saveAllWorlds(self: *Conduit) void {
        var worlds_it = self.worlds.valueIterator();
        while (worlds_it.next()) |world| {
            var dims_it = world.*.dimensions.valueIterator();
            while (dims_it.next()) |dim| {
                var chunk_iter = dim.*.chunks.valueIterator();
                while (chunk_iter.next()) |chunk| {
                    world.*.provider.writeChunkEntities(chunk.*, dim.*) catch {};
                    if (chunk.*.dirty) {
                        world.*.provider.writeChunk(chunk.*, dim.*) catch continue;
                    }
                }
            }
        }

        const snapshots = self.getPlayerSnapshots();
        for (snapshots) |player| {
            player.savePlayerData();
        }
    }

    pub fn deinit(self: *Conduit) void {
        self.raknet.running = false;
        self.raknet.socket.stop();
        if (self.raknet.tick_thread) |thread| {
            thread.join();
            self.raknet.tick_thread = null;
        }

        self.saveAllWorlds();

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

        self.raknet.deinit();

        deinitRegistries();
        ItemPalette.deinitRegistry();
        EntityTypeRegistry.EntityTypeRegistry.deinit();
        if (self.creative_content) |*cc| cc.deinit();
        self.config.deinit();
        self.events.deinit();
        self.network.deinit();
        self.tasks.deinit();
        self.threaded_tasks.deinit();
    }
};

const NBT = @import("nbt");

fn readLevelDatSpawn(allocator: std.mem.Allocator, path: []const u8) !Protocol.BlockPosition {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 8 * 1024 * 1024);
    defer allocator.free(data);
    if (data.len < 8) return error.InvalidLevelDat;

    var stream = BinaryStream.init(allocator, data[8..], null);
    defer stream.deinit();
    var root = try NBT.CompoundTag.read(&stream, allocator, NBT.ReadWriteOptions.default);
    defer root.deinit(allocator);

    const sx = switch (root.get("SpawnX") orelse return error.NoSpawn) {
        .Int => |t| t.value,
        else => return error.NoSpawn,
    };
    const sy = switch (root.get("SpawnY") orelse return error.NoSpawn) {
        .Int => |t| t.value,
        else => return error.NoSpawn,
    };
    const sz = switch (root.get("SpawnZ") orelse return error.NoSpawn) {
        .Int => |t| t.value,
        else => return error.NoSpawn,
    };

    return Protocol.BlockPosition{ .x = sx, .y = sy, .z = sz };
}
