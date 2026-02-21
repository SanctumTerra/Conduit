const std = @import("std");
const types = @import("types.zig");
const Event = types.Event;

pub fn Emitter() type {
    const event_fields = @typeInfo(Event).@"enum".fields;

    return struct {
        const Self = @This();

        const ListenerArrays = blk: {
            var fields: [event_fields.len * 3]std.builtin.Type.StructField = undefined;
            for (event_fields, 0..) |field, i| {
                const e: Event = @enumFromInt(field.value);
                const EventT = Event.DataType(e);
                const BeforeFn = *const fn (*EventT) bool;
                const OnFn = *const fn (*const EventT) void;
                const AfterFn = *const fn (*const EventT, bool) void;

                fields[i * 3] = .{
                    .name = field.name ++ "_before",
                    .type = std.ArrayListUnmanaged(BeforeFn),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(std.ArrayListUnmanaged(BeforeFn)),
                };
                fields[i * 3 + 1] = .{
                    .name = field.name ++ "_on",
                    .type = std.ArrayListUnmanaged(OnFn),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(std.ArrayListUnmanaged(OnFn)),
                };
                fields[i * 3 + 2] = .{
                    .name = field.name ++ "_after",
                    .type = std.ArrayListUnmanaged(AfterFn),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(std.ArrayListUnmanaged(AfterFn)),
                };
            }
            break :blk @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        allocator: std.mem.Allocator,
        listeners: ListenerArrays,

        pub fn init(allocator: std.mem.Allocator) Self {
            var listeners: ListenerArrays = undefined;
            inline for (event_fields) |field| {
                @field(listeners, field.name ++ "_before") = .{};
                @field(listeners, field.name ++ "_on") = .{};
                @field(listeners, field.name ++ "_after") = .{};
            }
            return .{ .allocator = allocator, .listeners = listeners };
        }

        pub fn deinit(self: *Self) void {
            inline for (event_fields) |field| {
                @field(self.listeners, field.name ++ "_before").deinit(self.allocator);
                @field(self.listeners, field.name ++ "_on").deinit(self.allocator);
                @field(self.listeners, field.name ++ "_after").deinit(self.allocator);
            }
        }

        pub fn before(self: *Self, comptime event: Event, cb: BeforeFnType(event)) !void {
            try @field(self.listeners, @tagName(event) ++ "_before").append(self.allocator, cb);
        }

        pub fn on(self: *Self, comptime event: Event, cb: OnFnType(event)) !void {
            try @field(self.listeners, @tagName(event) ++ "_on").append(self.allocator, cb);
        }

        pub fn after(self: *Self, comptime event: Event, cb: AfterFnType(event)) !void {
            try @field(self.listeners, @tagName(event) ++ "_after").append(self.allocator, cb);
        }

        pub fn emit(self: *Self, comptime event: Event, data: *Event.DataType(event)) bool {
            const name = @tagName(event);
            var cancelled = false;

            for (@field(self.listeners, name ++ "_before").items) |cb| {
                if (!cb(data)) {
                    cancelled = true;
                    break;
                }
            }

            if (!cancelled) {
                for (@field(self.listeners, name ++ "_on").items) |cb| {
                    cb(data);
                }
            }

            for (@field(self.listeners, name ++ "_after").items) |cb| {
                cb(data, cancelled);
            }

            return !cancelled;
        }

        fn BeforeFnType(comptime event: Event) type {
            return *const fn (*Event.DataType(event)) bool;
        }

        fn OnFnType(comptime event: Event) type {
            return *const fn (*const Event.DataType(event)) void;
        }

        fn AfterFnType(comptime event: Event) type {
            return *const fn (*const Event.DataType(event), bool) void;
        }
    };
}
