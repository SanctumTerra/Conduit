const std = @import("std");
const Logger = @import("Logger").Logger;
const FrameSet = @import("./proto/online/FrameSet.zig").FrameSet;
const CAllocator = @import("CAllocator");
const Frame = @import("./proto/Frame.zig").Frame;

const MAX_ACTIVE_FRAGMENTATIONS = 32;

pub const Fragment = struct {
    timestamp: i64,
    fragments: std.AutoHashMap(u32, Frame),
    split_id: u32,
    is_active: bool,

    pub fn activate(self: *Fragment, id: u32) void {
        self.timestamp = std.time.milliTimestamp();
        self.split_id = id;
        self.is_active = true;
        self.clearFrames();
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

pub const CommunicationData = struct {
    active_fragmentations: [MAX_ACTIVE_FRAGMENTATIONS]Fragment,

    pub fn init() CommunicationData {
        var self: CommunicationData = undefined;
        for (&self.active_fragmentations) |*frag_slot| {
            frag_slot.* = .{
                .timestamp = 0,
                .fragments = std.AutoHashMap(u32, Frame).init(CAllocator.get()),
                .split_id = 0,
                .is_active = false,
            };
        }
        return self;
    }

    pub fn deinit(self: *CommunicationData) void {
        for (&self.active_fragmentations) |*frag_slot| {
            frag_slot.deinit();
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

pub const Connection = struct {
    address: std.net.Address,
    communication_data: CommunicationData,

    pub fn init(address: std.net.Address) Connection {
        return .{ .address = address, .communication_data = CommunicationData.init() };
    }

    pub fn deinit(self: *Connection) void {
        self.communication_data.deinit();
    }

    pub fn handleFrameSet(self: *Connection, data: []const u8) void {
        const frame_set = FrameSet.deserialize(data);
        defer CAllocator.get().free(frame_set.frames);

        for (frame_set.frames) |frame_from_set| {
            self.handleFrame(frame_from_set);
        }
    }

    pub fn tick(self: *Connection) void {
        for (&self.communication_data.active_fragmentations) |*fragment_slot| {
            if (fragment_slot.is_active) {
                const timeout = 1000 * 15;
                if (fragment_slot.timestamp + timeout < std.time.milliTimestamp()) {
                    fragment_slot.deactivate();
                }
            }
        }
    }

    pub fn handleFrame(self: *Connection, frame: Frame) void {
        if (frame.payload.len > 0) {
            Logger.INFO("Handling frame, type: {}", .{frame.payload[0]});
        } else {
            Logger.INFO("Handling frame, empty payload", .{});
        }

        if (frame.isSplit()) {
            self.handleSplitFrame(frame);
        } else {
            Logger.INFO("Processing non-split frame directly.", .{});
            frame.deinit();
        }
    }

    pub fn handleSplitFrame(self: *Connection, frame: Frame) void {
        const split_id = frame.split_id.?;
        const split_index = frame.split_frame_index.?;
        const split_count = frame.split_size.?;

        const group_ptr = self.communication_data.findOrCreateFragmentSlot(split_id);

        if (group_ptr == null) {
            Logger.ERROR("Max fragment groups ({}) reached or error, cannot handle split_id: {}. Discarding frame.", .{
                MAX_ACTIVE_FRAGMENTATIONS, split_id,
            });
            frame.deinit();
            return;
        }
        var group = group_ptr.?;

        group.timestamp = std.time.milliTimestamp();

        group.fragments.put(split_index, frame) catch |err| {
            Logger.ERROR("Failed to put frame (index {}) in fragments for split_id {}: {}. Discarding frame.", .{
                split_index, split_id, err,
            });
            frame.deinit();
            return;
        };

        var fragments_count: usize = 0;
        var iter = group.fragments.iterator();
        while (iter.next()) |_| {
            fragments_count += 1;
        }

        if (fragments_count == @as(usize, split_count)) {
            var total_size: usize = 0;
            for (0..split_count) |i| {
                const s_frame_opt = group.fragments.get(@intCast(i));
                if (s_frame_opt == null) {
                    Logger.ERROR("Missing fragment at index {} for split_id={} during reassembly. Aborting reassembly for this attempt.", .{ i, split_id });
                    return;
                }
                total_size += s_frame_opt.?.payload.len;
            }

            const buffer = CAllocator.get().alloc(u8, total_size) catch |err| {
                Logger.ERROR("Failed to allocate buffer (size {}) for reassembly (split_id {}): {}. Aborting reassembly.", .{
                    total_size, split_id, err,
                });
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
            self.handleFrame(reassembled_frame);
        } else {}
    }
};
