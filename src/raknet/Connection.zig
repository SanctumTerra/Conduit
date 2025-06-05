const std = @import("std");
const Logger = @import("Logger").Logger;
const FrameSet = @import("./proto/online/FrameSet.zig").FrameSet;
const CAllocator = @import("CAllocator");
const Frame = @import("./proto/Frame.zig").Frame;
const Packets = @import("./proto/Packets.zig").Packets;
const ConnectionRequest = @import("./proto/online/ConnectionRequest.zig").ConnectionRequest;
const ConnectionRequestAccepted = @import("./proto/online/ConnectionRequestAccepted.zig").ConnectionRequestAccepted;
const Address = @import("./proto/Address.zig").Address;
const Reliability = @import("./proto/Frame.zig").Reliability;
const Server = @import("Server.zig").Server;
const ConnectedPing = @import("./proto/online/ConnectedPing.zig").ConnectedPing;
const ConnectedPong = @import("./proto/online/ConnectedPong.zig").ConnectedPong;
const Nack = @import("./proto/online/Nack.zig").Nack;
const Ack = @import("./proto/online/Ack.zig").Ack;

const MAX_ACTIVE_FRAGMENTATIONS = 32;
const MAX_ORDERING_QUEUE_SIZE = 64;
const MAX_BACKUP_SEQUENCES = 100;
const MAX_SEQUENCE_TRACKING = 500;
const FRAGMENT_TIMEOUT_MS = 10000;
const ORDERING_TIMEOUT_MS = 8000;
const CLEANUP_INTERVAL_MS = 2000;

pub const Priority = struct {
    pub const Immediate: u8 = 0;
    pub const Normal: u8 = 1;
    pub const Low: u8 = 2;
};

pub const Fragment = struct {
    timestamp: i64,
    fragments: std.AutoHashMap(u32, Frame),
    split_id: u32,
    is_active: bool,

    pub fn activate(self: *Fragment, id: u32) void {
        self.timestamp = std.time.milliTimestamp();
        self.split_id = id;
        self.is_active = true;
        if (self.fragments.count() > 0) {
            self.clearFrames();
        }
    }

    fn clearFrames(self: *Fragment) void {
        var iter = self.fragments.iterator();
        while (iter.next()) |entry| {
            var frame_to_deinit = entry.value_ptr.*;
            frame_to_deinit.deinit();
        }
        self.fragments.clearRetainingCapacity();
    }

    pub fn deactivate(self: *Fragment) void {
        self.clearFrames();
        self.is_active = false;
    }

    pub fn deinit(self: *Fragment) void {
        self.clearFrames();
        self.fragments.deinit();
        self.is_active = false;
    }
};

const OrderedFrameEntry = struct {
    frame: Frame,
    timestamp: i64,

    pub fn deinit(self: *OrderedFrameEntry) void {
        self.frame.deinit();
    }
};

pub const CommunicationData = struct {
    active_fragmentations: [MAX_ACTIVE_FRAGMENTATIONS]Fragment,
    input_order_index: [MAX_ACTIVE_FRAGMENTATIONS]u32,
    input_highest_sequence_index: [MAX_ACTIVE_FRAGMENTATIONS]u32,
    input_ordering_queue: [MAX_ACTIVE_FRAGMENTATIONS]std.AutoHashMap(u32, OrderedFrameEntry),
    output_order_index: [MAX_ACTIVE_FRAGMENTATIONS]u32,
    output_sequence_index: [MAX_ACTIVE_FRAGMENTATIONS]u32,
    output_reliable_index: u32,
    output_sequence: u32,
    output_split_index: u32,

    ordering_queue_initialized: [MAX_ACTIVE_FRAGMENTATIONS]bool,
    fragments_initialized: [MAX_ACTIVE_FRAGMENTATIONS]bool,

    pub fn init() CommunicationData {
        var self: CommunicationData = undefined;
        @memset(&self.input_order_index, 0);
        @memset(&self.input_highest_sequence_index, 0);
        @memset(&self.output_order_index, 0);
        @memset(&self.output_sequence_index, 0);
        @memset(&self.ordering_queue_initialized, false);
        @memset(&self.fragments_initialized, false);

        for (&self.active_fragmentations) |*frag_slot| {
            frag_slot.* = .{
                .timestamp = 0,
                .fragments = std.AutoHashMap(u32, Frame).init(CAllocator.get()),
                .split_id = 0,
                .is_active = false,
            };
            self.fragments_initialized[frag_slot - &self.active_fragmentations[0]] = true;
        }

        for (&self.input_ordering_queue) |*queue_slot| {
            queue_slot.* = std.AutoHashMap(u32, OrderedFrameEntry).init(CAllocator.get());
            self.ordering_queue_initialized[queue_slot - &self.input_ordering_queue[0]] = true;
        }

        self.output_reliable_index = 0;
        self.output_sequence = 0;
        self.output_split_index = 0;
        return self;
    }

    pub fn deinit(self: *CommunicationData) void {
        for (&self.active_fragmentations, 0..) |*frag_slot, i| {
            if (self.fragments_initialized[i]) {
                frag_slot.deinit();
            }
        }

        for (&self.input_ordering_queue, 0..) |*queue_slot, i| {
            if (self.ordering_queue_initialized[i]) {
                var iter = queue_slot.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit();
                }
                queue_slot.deinit();
            }
        }
    }

    fn findOrCreateFragmentSlot(self: *CommunicationData, split_id: u32) ?*Fragment {
        var available_slot: ?*Fragment = null;

        for (&self.active_fragmentations) |*slot| {
            if (slot.is_active) {
                if (slot.split_id == split_id) {
                    return slot;
                }
            } else {
                if (available_slot == null) {
                    available_slot = slot;
                }
            }
        }

        if (available_slot) |slot_to_activate| {
            slot_to_activate.activate(split_id);
            return slot_to_activate;
        }

        return null;
    }
};

pub const GamePacketCallbackFn = *const fn (data: []const u8, context: ?*anyopaque) void;

pub const Connection = struct {
    address: std.net.Address,
    key: []const u8,
    communication_data: CommunicationData,
    output_frame_queue: std.ArrayList(Frame),
    output_frames_byte_length: usize,
    output_backup: std.AutoHashMap(u24, []Frame),
    mtu_size: u16,
    server: ?*anyopaque,
    is_active: std.atomic.Value(bool),
    connected: bool,
    game_packet_callback: ?GamePacketCallbackFn = null,
    game_packet_context: ?*anyopaque = null,

    critical_section: std.Thread.Mutex,
    sequence_mutex: std.Thread.Mutex,
    backup_mutex: std.Thread.Mutex,
    output_mutex: std.Thread.Mutex,

    received_sequences: std.AutoHashMap(u24, void),
    lost_sequences: std.AutoHashMap(u24, void),
    last_input_sequence: i32,

    last_ack_time: i64,
    last_nack_time: i64,
    last_cleanup_time: i64,
    last_ping_time: i64,

    frames_created: u64,
    frames_destroyed: u64,
    last_leak_check: i64,

    pub fn init(address: std.net.Address, key: []const u8) Connection {
        var connection: Connection = undefined;

        connection.address = address;
        connection.key = key;
        connection.communication_data = CommunicationData.init();
        connection.output_frame_queue = std.ArrayList(Frame).init(CAllocator.get());
        connection.output_frames_byte_length = 0;
        connection.output_backup = std.AutoHashMap(u24, []Frame).init(CAllocator.get());
        connection.mtu_size = 1400;
        connection.server = null;
        connection.is_active = std.atomic.Value(bool).init(true);
        connection.connected = false;

        connection.critical_section = std.Thread.Mutex{};
        connection.sequence_mutex = std.Thread.Mutex{};
        connection.backup_mutex = std.Thread.Mutex{};
        connection.output_mutex = std.Thread.Mutex{};

        connection.received_sequences = std.AutoHashMap(u24, void).init(CAllocator.get());
        connection.lost_sequences = std.AutoHashMap(u24, void).init(CAllocator.get());
        connection.last_input_sequence = -1;

        const current_time = std.time.milliTimestamp();
        connection.last_ack_time = current_time;
        connection.last_nack_time = current_time;
        connection.last_cleanup_time = current_time;
        connection.last_ping_time = current_time;
        connection.last_leak_check = current_time;

        connection.frames_created = 0;
        connection.frames_destroyed = 0;

        connection.output_frame_queue.ensureTotalCapacity(8) catch {};

        return connection;
    }

    pub fn setServer(self: *Connection, server: *anyopaque) void {
        self.server = server;
    }

    pub fn deinit(self: *Connection) void {
        Logger.DEBUG("Deinitializing connection - created {d} frames, destroyed {d} frames", .{ self.frames_created, self.frames_destroyed });

        self.communication_data.deinit();

        self.sequence_mutex.lock();
        self.received_sequences.deinit();
        self.lost_sequences.deinit();
        self.sequence_mutex.unlock();

        self.output_mutex.lock();
        for (self.output_frame_queue.items) |*frame| {
            frame.deinit();
            self.frames_destroyed += 1;
        }
        self.output_frame_queue.deinit();
        self.output_mutex.unlock();

        self.backup_mutex.lock();
        var backup_iter = self.output_backup.iterator();
        while (backup_iter.next()) |entry| {
            const sequence = entry.key_ptr.*;
            self.clearBackupFramesUnsafe(sequence);
        }
        self.output_backup.deinit();
        self.backup_mutex.unlock();

        std.heap.page_allocator.free(self.key);
    }

    fn trackFrameCreation(self: *Connection) void {
        self.frames_created += 1;
    }

    fn trackFrameDestruction(self: *Connection) void {
        self.frames_destroyed += 1;
    }

    pub fn tick(self: *Connection) void {
        if (!self.is_active.load(.acquire)) return;

        const now = std.time.milliTimestamp();
        const ping_timeout = 30000;

        if (now - self.last_ping_time > ping_timeout) {
            Logger.DEBUG("Connection ping timeout - no ConnectedPing received for {d}ms, disconnecting", .{now - self.last_ping_time});
            self.onDisconnect();
            return;
        }

        if (now - self.last_cleanup_time >= CLEANUP_INTERVAL_MS) {
            self.performCleanup();
            self.last_cleanup_time = now;
        }

        if (now - self.last_leak_check >= 10000) {
            const frame_diff = self.frames_created - self.frames_destroyed;
            if (frame_diff > 1000) {
                Logger.WARN("Potential frame leak detected: created {d}, destroyed {d}, diff {d}", .{ self.frames_created, self.frames_destroyed, frame_diff });
                self.emergencyCleanup();
            }
            self.last_leak_check = now;
        }

        self.sendAcksAndNacks();

        self.output_mutex.lock();
        const queue_len = self.output_frame_queue.items.len;
        self.output_mutex.unlock();

        if (queue_len > 0) {
            self.sendQueue(queue_len);
        }
    }

    fn performCleanup(self: *Connection) void {
        const current_time = std.time.milliTimestamp();
        var cleaned_items: usize = 0;

        self.critical_section.lock();
        for (&self.communication_data.active_fragmentations) |*fragment_slot| {
            if (fragment_slot.is_active) {
                if (current_time - fragment_slot.timestamp > FRAGMENT_TIMEOUT_MS) {
                    const count = fragment_slot.fragments.count();
                    fragment_slot.deactivate();
                    cleaned_items += count;
                    self.frames_destroyed += count;
                }
            }
        }
        for (&self.communication_data.input_ordering_queue, 0..) |*queue_slot, queue_idx| {
            if (!self.communication_data.ordering_queue_initialized[queue_idx]) continue;

            if (queue_slot.count() > MAX_ORDERING_QUEUE_SIZE) {
                Logger.WARN("Ordering queue {d} exceeded limit ({d} entries), clearing", .{ queue_idx, queue_slot.count() });
                var iter = queue_slot.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit();
                    cleaned_items += 1;
                    self.frames_destroyed += 1;
                }
                queue_slot.clearRetainingCapacity();
            } else {
                var to_remove = std.ArrayList(u32).init(CAllocator.get());
                defer to_remove.deinit();

                var iter = queue_slot.iterator();
                while (iter.next()) |entry| {
                    const ordered_entry = entry.value_ptr.*;
                    if (current_time - ordered_entry.timestamp > ORDERING_TIMEOUT_MS) {
                        to_remove.append(entry.key_ptr.*) catch continue;
                    }
                }

                for (to_remove.items) |frame_index| {
                    if (queue_slot.get(frame_index)) |entry| {
                        var mutable_entry = entry;
                        mutable_entry.deinit();
                        cleaned_items += 1;
                        self.frames_destroyed += 1;
                    }
                    _ = queue_slot.remove(frame_index);
                }
            }
        }
        self.critical_section.unlock();

        self.backup_mutex.lock();
        if (self.output_backup.count() > MAX_BACKUP_SEQUENCES) {
            var sequences_to_remove = std.ArrayList(u24).init(CAllocator.get());
            defer sequences_to_remove.deinit();

            var iter = self.output_backup.keyIterator();
            var count: usize = 0;
            const target_remove = self.output_backup.count() - MAX_BACKUP_SEQUENCES;

            while (iter.next()) |key| {
                sequences_to_remove.append(key.*) catch continue;
                count += 1;
                if (count >= target_remove) break;
            }

            for (sequences_to_remove.items) |seq| {
                self.clearBackupFramesUnsafe(seq);
            }
            cleaned_items += sequences_to_remove.items.len;
        }
        self.backup_mutex.unlock();
        self.sequence_mutex.lock();
        if (self.received_sequences.count() > MAX_SEQUENCE_TRACKING) {
            const old_count = self.received_sequences.count();
            self.received_sequences.clearRetainingCapacity();
            cleaned_items += old_count;
        }

        if (self.lost_sequences.count() > MAX_SEQUENCE_TRACKING / 2) {
            const old_count = self.lost_sequences.count();
            self.lost_sequences.clearRetainingCapacity();
            cleaned_items += old_count;
        }
        self.sequence_mutex.unlock();

        if (cleaned_items > 0) {
            Logger.INFO("Cleanup completed: removed {d} items", .{cleaned_items});
        }
    }

    fn emergencyCleanup(self: *Connection) void {
        Logger.WARN("Emergency cleanup triggered!", .{});

        self.backup_mutex.lock();
        var backup_iter = self.output_backup.iterator();
        while (backup_iter.next()) |entry| {
            const frames = entry.value_ptr.*;
            for (frames) |*frame| {
                frame.deinit();
                self.frames_destroyed += 1;
            }
            CAllocator.get().free(frames);
        }
        self.output_backup.clearRetainingCapacity();
        self.backup_mutex.unlock();

        self.sequence_mutex.lock();
        self.received_sequences.clearRetainingCapacity();
        self.lost_sequences.clearRetainingCapacity();
        self.sequence_mutex.unlock();
        self.critical_section.lock();
        for (&self.communication_data.active_fragmentations) |*frag_slot| {
            if (frag_slot.is_active) {
                const count = frag_slot.fragments.count();
                frag_slot.deactivate();
                self.frames_destroyed += count;
            }
        }

        for (&self.communication_data.input_ordering_queue, 0..) |*queue_slot, i| {
            if (self.communication_data.ordering_queue_initialized[i]) {
                var iter = queue_slot.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit();
                    self.frames_destroyed += 1;
                }
                queue_slot.clearRetainingCapacity();
            }
        }
        self.critical_section.unlock();

        Logger.INFO("Emergency cleanup completed - frame stats reset", .{});
    }

    fn sendAcksAndNacks(self: *Connection) void {
        const current_time = std.time.milliTimestamp();
        const ack_interval = 100;

        self.sequence_mutex.lock();
        const should_send_acks = current_time - self.last_ack_time >= ack_interval and self.received_sequences.count() > 0;
        const should_send_nacks = current_time - self.last_nack_time >= ack_interval and self.lost_sequences.count() > 0;

        if (should_send_acks) {
            self.last_ack_time = current_time;
            self.sendAcksUnsafe();
        }

        if (should_send_nacks) {
            self.last_nack_time = current_time;
            self.sendNacksUnsafe();
        }
        self.sequence_mutex.unlock();
    }

    fn sendAcksUnsafe(self: *Connection) void {
        if (self.received_sequences.count() == 0) return;

        var sequences_list = std.ArrayList(u32).init(CAllocator.get());
        defer sequences_list.deinit();

        var iter = self.received_sequences.keyIterator();
        while (iter.next()) |key| {
            sequences_list.append(key.*) catch continue;
        }

        self.received_sequences.clearRetainingCapacity();

        if (sequences_list.items.len == 0) return;

        var ack = Ack.init(sequences_list.items, CAllocator.get()) catch return;
        defer ack.deinit();

        const serialized = ack.serialize();
        defer CAllocator.get().free(serialized);
        self.send(serialized);
    }

    fn sendNacksUnsafe(self: *Connection) void {
        if (self.lost_sequences.count() == 0) return;

        var sequences_list = std.ArrayList(u32).init(CAllocator.get());
        defer sequences_list.deinit();

        var iter = self.lost_sequences.keyIterator();
        while (iter.next()) |key| {
            sequences_list.append(key.*) catch continue;
        }

        self.lost_sequences.clearRetainingCapacity();

        if (sequences_list.items.len == 0) return;

        var nack = Nack.init(sequences_list.items, CAllocator.get()) catch return;
        defer nack.deinit();

        const serialized = nack.serialize();
        defer CAllocator.get().free(serialized);
        self.send(serialized);
    }

    pub fn handlePacket(self: *Connection, data: []const u8) void {
        if (data.len == 0) {
            Logger.WARN("handlePacket called with empty data", .{});
            return;
        }

        const id = data[0];

        if (id == Packets.ConnectionRequest) {
            self.handleConnectionRequest(data);
            return;
        }

        switch (id) {
            Packets.ConnectedPing => self.handleConnectedPing(data),
            Packets.Ack => self.handleAck(data),
            Packets.Nack => self.handleNack(data),
            Packets.DisconnectNotification => {
                self.onDisconnect();
            },
            Packets.NewIncomingConnection => {
                if (self.connected) return;
                if (self.server) |server_ptr| {
                    const server = @as(*Server, @ptrCast(@alignCast(server_ptr)));
                    if (server.connection_callback) |callback| {
                        callback(self, server.connection_context);
                    }
                    self.connected = true;
                }
            },
            254 => {
                if (self.game_packet_callback) |callback| {
                    callback(data, self.game_packet_context);
                }
            },
            else => Logger.ERROR("Unknown packet ID {d}", .{id}),
        }
    }

    pub fn setGamePacketCallback(self: *Connection, callback: GamePacketCallbackFn, context: ?*anyopaque) void {
        self.game_packet_callback = callback;
        self.game_packet_context = context;
    }

    fn handleConnectionRequest(self: *Connection, data: []const u8) void {
        const connection_request = ConnectionRequest.deserialize(data);
        const empty_address = Address.init(4, "0.0.0.0", 0);
        var connection_request_accepted = ConnectionRequestAccepted.init(empty_address, 0, empty_address, connection_request.timestamp, std.time.milliTimestamp());

        const serialized = connection_request_accepted.serialize();
        defer CAllocator.get().free(serialized);

        const frame = self.frameIn(serialized);
        self.sendFrame(frame, Priority.Immediate);
    }

    fn handleConnectedPing(self: *Connection, data: []const u8) void {
        const connected_ping = ConnectedPing.deserialize(data);
        self.last_ping_time = std.time.milliTimestamp();

        var connected_pong = ConnectedPong.init(connected_ping.timestamp, std.time.milliTimestamp());
        const serialized = connected_pong.serialize();
        defer CAllocator.get().free(serialized);

        const frame = self.frameIn(serialized);
        self.sendFrame(frame, Priority.Immediate);
    }

    pub fn frameIn(self: *Connection, msg: []const u8) Frame {
        self.trackFrameCreation();
        if (msg.len == 0) {
            return Frame.init(null, null, null, 0, Reliability.ReliableOrdered, &[_]u8{}, null, null, null, CAllocator.get());
        }

        const payload_copy = CAllocator.get().dupe(u8, msg) catch |err| {
            Logger.ERROR("Failed to duplicate payload: {}", .{err});
            return Frame.init(null, null, null, 0, Reliability.ReliableOrdered, &[_]u8{}, null, null, null, CAllocator.get());
        };
        return Frame.init(null, null, null, 0, Reliability.ReliableOrdered, payload_copy, null, null, null, CAllocator.get());
    }

    pub fn handleFrameSet(self: *Connection, data: []const u8) void {
        if (!self.is_active.load(.acquire)) return;

        const frame_set = FrameSet.deserialize(data);
        const sequence = frame_set.sequence_number;

        self.sequence_mutex.lock();
        const is_duplicate = (self.last_input_sequence != -1 and sequence <= @as(u24, @intCast(@max(0, self.last_input_sequence)))) or self.received_sequences.contains(sequence);
        if (is_duplicate) {
            self.sequence_mutex.unlock();
            for (frame_set.frames) |*frame| {
                frame.deinit();
            }
            CAllocator.get().free(frame_set.frames);
            return;
        }

        self.received_sequences.put(sequence, {}) catch {};
        _ = self.lost_sequences.remove(sequence);

        const last_seq = @as(u24, @intCast(@max(0, self.last_input_sequence)));
        if (sequence > last_seq + 1) {
            var i: u24 = last_seq + 1;
            while (i < sequence) : (i += 1) {
                self.lost_sequences.put(i, {}) catch {};
            }
        }

        self.last_input_sequence = @as(i32, @intCast(sequence));
        self.sequence_mutex.unlock();

        for (frame_set.frames, 0..) |frame_from_set, frame_idx| {
            if (frame_from_set.payload.len > 0) {
                const payload_copy = CAllocator.get().dupe(u8, frame_from_set.payload) catch |err| {
                    Logger.ERROR("Failed to clone frame payload for frame #{d}: {}", .{ frame_idx, err });
                    continue;
                };

                const frame_copy = Frame.init(frame_from_set.reliable_frame_index, frame_from_set.sequence_frame_index, frame_from_set.ordered_frame_index, frame_from_set.order_channel, frame_from_set.reliability, payload_copy, frame_from_set.split_frame_index, frame_from_set.split_id, frame_from_set.split_size, CAllocator.get());

                self.trackFrameCreation();
                self.handleFrame(frame_copy);
            }
        }

        for (frame_set.frames) |*frame| {
            frame.deinit();
        }
        CAllocator.get().free(frame_set.frames);
    }

    pub fn handleFrame(self: *Connection, frame: Frame) void {
        if (!self.is_active.load(.acquire)) {
            frame.deinit();
            self.trackFrameDestruction();
            return;
        }

        if (frame.payload.len == 0) {
            Logger.WARN("Frame has empty payload - skipping in handleFrame", .{});
            frame.deinit();
            self.trackFrameDestruction();
            return;
        }

        if (frame.isSplit()) {
            self.handleSplitFrame(frame);
        } else if (frame.isSequenced()) {
            self.handleSequencedFrame(frame);
        } else if (frame.isOrdered()) {
            self.handleOrderedFrame(frame);
        } else {
            self.handlePacket(frame.payload);
            frame.deinit();
            self.trackFrameDestruction();
        }
    }

    pub fn handleSplitFrame(self: *Connection, frame: Frame) void {
        if (!self.is_active.load(.acquire)) {
            frame.deinit();
            self.trackFrameDestruction();
            return;
        }

        var frame_to_handle: ?Frame = null;
        var should_free_original = true;

        {
            self.critical_section.lock();
            defer self.critical_section.unlock();

            if (!self.is_active.load(.acquire)) {
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            const split_id = frame.split_id.?;
            const split_index = frame.split_frame_index.?;
            const split_count = frame.split_size.?;

            if (split_count > 256 or split_index >= split_count) {
                Logger.ERROR("Invalid split parameters: split_count={d}, split_index={d}", .{ split_count, split_index });
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            const group_ptr = self.communication_data.findOrCreateFragmentSlot(split_id);
            if (group_ptr == null) {
                Logger.ERROR("Cannot find or create fragment slot for split_id {d}", .{split_id});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            var group = group_ptr.?;
            group.timestamp = std.time.milliTimestamp();
            if (group.fragments.count() > 256) {
                Logger.WARN("Fragment group {d} has too many fragments, clearing", .{split_id});
                group.deactivate();
                group.activate(split_id);
            }

            group.fragments.put(split_index, frame) catch |err| {
                Logger.ERROR("Failed to store fragment: {}", .{err});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            };

            should_free_original = false;

            if (group.fragments.count() == @as(usize, split_count)) {
                var has_all_fragments = true;
                for (0..split_count) |i| {
                    if (!group.fragments.contains(@intCast(i))) {
                        has_all_fragments = false;
                        break;
                    }
                }

                if (!has_all_fragments) {
                    Logger.ERROR("Missing fragments for split_id {d}", .{split_id});
                    return;
                }

                var total_size: usize = 0;
                for (0..split_count) |i| {
                    const s_frame = group.fragments.get(@intCast(i)).?;
                    total_size += s_frame.payload.len;
                }

                if (total_size > 1024 * 1024) {
                    Logger.ERROR("Reassembled frame too large: {d} bytes", .{total_size});
                    group.deactivate();
                    return;
                }

                const buffer = CAllocator.get().alloc(u8, total_size) catch |err| {
                    Logger.ERROR("Failed to allocate reassembly buffer: {}", .{err});
                    group.deactivate();
                    return;
                };

                var offset: usize = 0;
                for (0..split_count) |i| {
                    const s_frame = group.fragments.get(@intCast(i)).?;
                    std.mem.copyForwards(u8, buffer[offset..], s_frame.payload);
                    offset += s_frame.payload.len;
                }

                const reassembled_frame = Frame{
                    .reliability = frame.reliability,
                    .reliable_frame_index = frame.reliable_frame_index,
                    .sequence_frame_index = frame.sequence_frame_index,
                    .ordered_frame_index = frame.ordered_frame_index,
                    .order_channel = frame.order_channel,
                    .payload = buffer,
                    .split_id = null,
                    .split_size = 0,
                    .split_frame_index = null,
                    .allocator = CAllocator.get(),
                };

                group.deactivate();
                frame_to_handle = reassembled_frame;
                self.trackFrameCreation();
            }
        }
        if (should_free_original) {
            frame.deinit();
            self.trackFrameDestruction();
        }

        if (frame_to_handle) |reassembled_frame| {
            self.handleFrame(reassembled_frame);
        }
    }

    pub fn handleSequencedFrame(self: *Connection, frame: Frame) void {
        if (!self.is_active.load(.acquire)) {
            frame.deinit();
            self.trackFrameDestruction();
            return;
        }

        var payload_to_handle: ?[]u8 = null;

        {
            self.critical_section.lock();
            defer self.critical_section.unlock();

            if (!self.is_active.load(.acquire)) {
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            const channel = frame.order_channel orelse {
                Logger.ERROR("Sequenced frame missing order_channel", .{});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            };

            if (channel >= MAX_ACTIVE_FRAGMENTATIONS) {
                Logger.ERROR("Invalid channel: {d}", .{channel});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            const frame_index = frame.sequence_frame_index orelse {
                Logger.ERROR("Sequenced frame missing sequence_frame_index", .{});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            };

            const order_index = frame.ordered_frame_index orelse {
                Logger.ERROR("Sequenced frame missing ordered_frame_index", .{});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            };

            const current_highest = self.communication_data.input_highest_sequence_index[channel];
            if (frame_index >= current_highest and order_index >= self.communication_data.input_order_index[channel]) {
                self.communication_data.input_highest_sequence_index[channel] = frame_index + 1;

                payload_to_handle = CAllocator.get().dupe(u8, frame.payload) catch {
                    Logger.ERROR("Failed to copy payload for sequenced frame", .{});
                    frame.deinit();
                    self.trackFrameDestruction();
                    return;
                };
            }

            frame.deinit();
            self.trackFrameDestruction();
        }

        if (payload_to_handle) |payload| {
            defer CAllocator.get().free(payload);
            self.handlePacket(payload);
        }
    }

    pub fn handleOrderedFrame(self: *Connection, frame: Frame) void {
        if (!self.is_active.load(.acquire)) {
            frame.deinit();
            self.trackFrameDestruction();
            return;
        }

        var payloads_to_process = std.ArrayList([]u8).init(CAllocator.get());
        defer {
            for (payloads_to_process.items) |payload| {
                CAllocator.get().free(payload);
            }
            payloads_to_process.deinit();
        }

        {
            self.critical_section.lock();
            defer self.critical_section.unlock();

            if (!self.is_active.load(.acquire)) {
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            const channel = frame.order_channel orelse {
                Logger.ERROR("Ordered frame missing order_channel", .{});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            };

            if (channel >= MAX_ACTIVE_FRAGMENTATIONS) {
                Logger.ERROR("Invalid channel: {d}", .{channel});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }

            const frame_index = frame.ordered_frame_index orelse {
                Logger.ERROR("Ordered frame missing ordered_frame_index", .{});
                frame.deinit();
                self.trackFrameDestruction();
                return;
            };

            var expected_index = self.communication_data.input_order_index[channel];
            var queue = &self.communication_data.input_ordering_queue[channel];

            if (frame_index == expected_index) {
                const payload_copy = CAllocator.get().dupe(u8, frame.payload) catch {
                    Logger.ERROR("Failed to copy payload for ordered frame", .{});
                    frame.deinit();
                    self.trackFrameDestruction();
                    return;
                };

                payloads_to_process.append(payload_copy) catch {
                    CAllocator.get().free(payload_copy);
                    frame.deinit();
                    self.trackFrameDestruction();
                    return;
                };

                frame.deinit();
                self.trackFrameDestruction();
                expected_index += 1;

                while (queue.count() > 0) {
                    const entry_opt = queue.get(expected_index);
                    if (entry_opt == null) break;

                    var entry = entry_opt.?;
                    _ = queue.remove(expected_index);

                    const queue_payload_copy = CAllocator.get().dupe(u8, entry.frame.payload) catch {
                        entry.deinit();
                        self.trackFrameDestruction();
                        break;
                    };

                    payloads_to_process.append(queue_payload_copy) catch {
                        CAllocator.get().free(queue_payload_copy);
                        entry.deinit();
                        self.trackFrameDestruction();
                        break;
                    };

                    entry.deinit();
                    self.trackFrameDestruction();
                    expected_index += 1;
                }

                self.communication_data.input_order_index[channel] = expected_index;
                self.communication_data.input_highest_sequence_index[channel] = 0;
            } else if (frame_index > expected_index) {
                if (queue.count() >= MAX_ORDERING_QUEUE_SIZE) {
                    Logger.WARN("Ordering queue {d} full, discarding frame", .{channel});
                    frame.deinit();
                    self.trackFrameDestruction();
                    return;
                }

                if (frame_index - expected_index > 100) {
                    Logger.WARN("Frame too far ahead (expected {d}, got {d}), discarding", .{ expected_index, frame_index });
                    frame.deinit();
                    self.trackFrameDestruction();
                    return;
                }

                const entry = OrderedFrameEntry{ .frame = frame, .timestamp = std.time.milliTimestamp() };
                queue.put(frame_index, entry) catch |err| {
                    Logger.ERROR("Failed to queue ordered frame: {}", .{err});
                    frame.deinit();
                    self.trackFrameDestruction();
                    return;
                };
                return;
            } else {
                frame.deinit();
                self.trackFrameDestruction();
                return;
            }
        }

        for (payloads_to_process.items) |payload| {
            self.handlePacket(payload);
        }
    }

    pub fn handleAck(self: *Connection, data: []const u8) void {
        var ack = Ack.deserialize(data);
        defer ack.deinit();

        if (ack.sequences.len == 0) return;

        var cleared_count: usize = 0;
        self.backup_mutex.lock();
        for (ack.sequences) |sequence| {
            const seq = @as(u24, @truncate(sequence));
            if (self.output_backup.contains(seq)) {
                cleared_count += 1;
                self.clearBackupFramesUnsafe(seq);
            }
        }
        self.backup_mutex.unlock();
    }

    pub fn handleNack(self: *Connection, data: []const u8) void {
        var nack = Nack.deserialize(data);
        defer nack.deinit();

        for (nack.sequences) |sequence| {
            const seq = @as(u24, @truncate(sequence));
            self.resendFrameSet(seq);
        }
    }

    fn clearBackupFramesUnsafe(self: *Connection, sequence: u24) void {
        if (self.output_backup.get(sequence)) |frames| {
            for (frames) |*frame| {
                frame.deinit();
                self.trackFrameDestruction();
            }
            CAllocator.get().free(frames);
            _ = self.output_backup.remove(sequence);
        }
    }

    fn resendFrameSet(self: *Connection, sequence: u24) void {
        self.backup_mutex.lock();
        const frames_opt = self.output_backup.get(sequence);
        if (frames_opt) |frames| {
            var frameset = FrameSet.init(sequence, frames);
            const serialized = frameset.serialize();
            defer CAllocator.get().free(serialized);
            self.backup_mutex.unlock();
            self.send(serialized);
        } else {
            self.backup_mutex.unlock();
        }
    }

    pub fn sendFrame(self: *Connection, frame: Frame, priority: u8) void {
        const channel_index = frame.order_channel orelse 0;
        const channel = @as(usize, channel_index);

        var mutable_frame = frame;

        if (mutable_frame.isSequenced()) {
            mutable_frame.ordered_frame_index = self.communication_data.output_order_index[channel];
            mutable_frame.sequence_frame_index = self.communication_data.output_sequence_index[channel];
            self.communication_data.output_sequence_index[channel] += 1;
        } else if (mutable_frame.isOrdered()) {
            mutable_frame.ordered_frame_index = self.communication_data.output_order_index[channel];
            self.communication_data.output_order_index[channel] += 1;
            self.communication_data.output_sequence_index[channel] = 0;
        }

        const payload_size = mutable_frame.payload.len;
        const max_size = self.mtu_size - 36;

        if (payload_size <= max_size) {
            if (mutable_frame.isReliable()) {
                mutable_frame.reliable_frame_index = self.communication_data.output_reliable_index;
                self.communication_data.output_reliable_index += 1;
            }
            self.queueFrame(mutable_frame, priority);
            return;
        }

        const split_size = @divFloor(payload_size + max_size - 1, max_size);
        self.handleLargePayload(&mutable_frame, max_size, split_size);
    }

    fn handleLargePayload(self: *Connection, frame: *Frame, max_size: usize, split_size: usize) void {
        const split_id = @as(u16, @truncate(self.communication_data.output_split_index));
        self.communication_data.output_split_index += 1;

        var index: usize = 0;
        var split_frame_index: u32 = 0;

        while (index < frame.payload.len) {
            const end_index = @min(index + max_size, frame.payload.len);
            const chunk = frame.payload[index..end_index];

            const chunk_copy = CAllocator.get().dupe(u8, chunk) catch |err| {
                Logger.ERROR("Failed to duplicate chunk for split frame: {}", .{err});
                return;
            };

            const nframe = Frame.init(self.communication_data.output_reliable_index, frame.sequence_frame_index, frame.ordered_frame_index, frame.order_channel, frame.reliability, chunk_copy, split_frame_index, split_id, @as(u32, @intCast(split_size)), CAllocator.get());

            self.trackFrameCreation();
            self.communication_data.output_reliable_index += 1;
            split_frame_index += 1;

            self.queueFrame(nframe, Priority.Immediate);
            index = end_index;
        }

        frame.deinit();
        self.trackFrameDestruction();
    }

    fn queueFrame(self: *Connection, frame: Frame, priority: u8) void {
        const frame_length = frame.getByteLength();

        self.output_mutex.lock();
        self.output_frame_queue.append(frame) catch {
            Logger.ERROR("Failed to queue frame", .{});
            self.output_mutex.unlock();
            var frame_to_free = frame;
            frame_to_free.deinit();
            self.trackFrameDestruction();
            return;
        };

        self.output_frames_byte_length += frame_length;
        const should_send_immediately = priority == Priority.Immediate;
        const queue_len = self.output_frame_queue.items.len;
        self.output_mutex.unlock();

        if (should_send_immediately) {
            self.sendQueue(queue_len);
        }
    }

    pub fn sendQueue(self: *Connection, amount: usize) void {
        self.output_mutex.lock();
        if (self.output_frame_queue.items.len == 0) {
            self.output_mutex.unlock();
            return;
        }

        const actual_amount = @min(amount, self.output_frame_queue.items.len);
        const frames_to_send = self.output_frame_queue.items[0..actual_amount];

        var frames_for_backup = CAllocator.get().alloc(Frame, frames_to_send.len) catch {
            Logger.ERROR("Failed to allocate frames for backup", .{});
            self.output_mutex.unlock();
            return;
        };

        for (frames_to_send, 0..) |frame, i| {
            const payload_copy = if (frame.payload.len > 0)
                CAllocator.get().dupe(u8, frame.payload) catch {
                    Logger.ERROR("Failed to duplicate frame payload for backup", .{});
                    for (0..i) |j| {
                        frames_for_backup[j].deinit();
                        self.trackFrameDestruction();
                    }
                    CAllocator.get().free(frames_for_backup);
                    self.output_mutex.unlock();
                    return;
                }
            else
                &[_]u8{};

            frames_for_backup[i] = Frame.init(frame.reliable_frame_index, frame.sequence_frame_index, frame.ordered_frame_index, frame.order_channel, frame.reliability, payload_copy, frame.split_frame_index, frame.split_id, frame.split_size, CAllocator.get());
            self.trackFrameCreation();
        }
        self.output_mutex.unlock();

        const sequence = @as(u24, @truncate(self.communication_data.output_sequence));
        self.communication_data.output_sequence += 1;

        var frameset = FrameSet.init(sequence, frames_for_backup);
        const serialized = frameset.serialize();
        defer CAllocator.get().free(serialized);

        self.backup_mutex.lock();
        if (self.output_backup.contains(sequence)) {
            self.clearBackupFramesUnsafe(sequence);
        }
        self.output_backup.put(sequence, frames_for_backup) catch |err| {
            Logger.ERROR("Failed to store backup frames: {}", .{err});
            for (frames_for_backup) |*frame| {
                frame.deinit();
                self.trackFrameDestruction();
            }
            CAllocator.get().free(frames_for_backup);
            self.backup_mutex.unlock();
            return;
        };
        self.backup_mutex.unlock();

        self.updateOutputQueue(actual_amount);
        self.send(serialized);
    }

    fn updateOutputQueue(self: *Connection, amount: usize) void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        if (amount >= self.output_frame_queue.items.len) {
            for (self.output_frame_queue.items) |*frame| {
                frame.deinit();
                self.trackFrameDestruction();
            }
            self.output_frame_queue.clearRetainingCapacity();
            self.output_frames_byte_length = 0;
        } else {
            var removed_size: usize = 0;
            for (self.output_frame_queue.items[0..amount]) |*frame| {
                removed_size += frame.getByteLength();
                frame.deinit();
                self.trackFrameDestruction();
            }
            const remaining_count = self.output_frame_queue.items.len - amount;
            for (0..remaining_count) |i| {
                self.output_frame_queue.items[i] = self.output_frame_queue.items[i + amount];
            }
            self.output_frame_queue.shrinkRetainingCapacity(remaining_count);
            self.output_frames_byte_length -= removed_size;
        }
    }

    pub fn send(self: *Connection, data: []const u8) void {
        if (self.server) |server_ptr| {
            const server = @as(*Server, @ptrCast(@alignCast(server_ptr)));
            server.send(data, self.address);
        }
    }

    pub fn frameAndSend(self: *Connection, payload: []const u8, priority: u8) void {
        const frame = self.frameIn(payload);
        self.sendFrame(frame, priority);
    }

    pub fn dumpMemoryStats(self: *Connection) void {
        Logger.INFO("=== CONNECTION MEMORY STATS ===", .{});
        Logger.INFO("Frames: created {d}, destroyed {d}, diff {d}", .{ self.frames_created, self.frames_destroyed, self.frames_created - self.frames_destroyed });

        self.output_mutex.lock();
        const output_queue_len = self.output_frame_queue.items.len;
        self.output_mutex.unlock();

        self.backup_mutex.lock();
        const backup_count = self.output_backup.count();
        self.backup_mutex.unlock();

        self.sequence_mutex.lock();
        const received_count = self.received_sequences.count();
        const lost_count = self.lost_sequences.count();
        self.sequence_mutex.unlock();

        Logger.INFO("Output queue: {d} frames", .{output_queue_len});
        Logger.INFO("Backup sequences: {d}", .{backup_count});
        Logger.INFO("Received sequences: {d}", .{received_count});
        Logger.INFO("Lost sequences: {d}", .{lost_count});

        var total_ordering_entries: usize = 0;
        var total_fragment_entries: usize = 0;
        var active_fragment_groups: usize = 0;

        self.critical_section.lock();
        for (&self.communication_data.input_ordering_queue) |*queue_slot| {
            total_ordering_entries += queue_slot.count();
        }

        for (&self.communication_data.active_fragmentations) |*frag_slot| {
            if (frag_slot.is_active) {
                active_fragment_groups += 1;
                total_fragment_entries += frag_slot.fragments.count();
            }
        }
        self.critical_section.unlock();

        Logger.INFO("Ordering queue entries: {d}", .{total_ordering_entries});
        Logger.INFO("Fragment groups: {d} active, {d} total entries", .{ active_fragment_groups, total_fragment_entries });
        Logger.INFO("==============================", .{});
    }

    pub fn onDisconnect(self: *Connection) void {
        if (!self.is_active.load(.acquire)) {
            return;
        }

        Logger.DEBUG("Disconnecting connection", .{});
        self.deactivate();

        if (self.server) |server_ptr| {
            const server = @as(*Server, @ptrCast(@alignCast(server_ptr)));
            server.disconnectClient(self.address, self.key);
        }
    }

    pub fn deactivate(self: *Connection) void {
        var addr_buf: [48]u8 = undefined;
        const addr_str = std.fmt.bufPrint(&addr_buf, "{any}", .{self.address}) catch "unknown_addr";

        if (self.is_active.load(.acquire)) {
            Logger.DEBUG("Deactivating connection for {s}", .{addr_str});
            self.is_active.store(false, .release);
            self.game_packet_callback = null;
            self.game_packet_context = null;
            self.connected = false;
            Logger.DEBUG("Connection for {s} fully deactivated, callbacks nulled.", .{addr_str});
        } else {
            Logger.DEBUG("Connection for {s} already inactive.", .{addr_str});
        }
    }

    pub fn verifyCleanup(self: *Connection) void {
        const frame_diff = self.frames_created - self.frames_destroyed;
        if (frame_diff != 0) {
            Logger.WARN("Connection cleanup verification failed: {d} frames not properly cleaned up", .{frame_diff});
            self.dumpMemoryStats();
        }
    }
};
