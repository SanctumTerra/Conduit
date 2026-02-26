const std = @import("std");

const c = struct {
    extern fn leveldb_open(options: *leveldb_options_t, name: [*:0]const u8, errptr: *?[*:0]u8) ?*leveldb_t;
    extern fn leveldb_close(db: *leveldb_t) void;
    extern fn leveldb_put(db: *leveldb_t, options: *leveldb_writeoptions_t, key: [*]const u8, keylen: usize, val: [*]const u8, vallen: usize, errptr: *?[*:0]u8) void;
    extern fn leveldb_get(db: *leveldb_t, options: *leveldb_readoptions_t, key: [*]const u8, keylen: usize, vallen: *usize, errptr: *?[*:0]u8) ?[*]u8;
    extern fn leveldb_delete(db: *leveldb_t, options: *leveldb_writeoptions_t, key: [*]const u8, keylen: usize, errptr: *?[*:0]u8) void;
    extern fn leveldb_write(db: *leveldb_t, options: *leveldb_writeoptions_t, batch: *leveldb_writebatch_t, errptr: *?[*:0]u8) void;
    extern fn leveldb_options_create() ?*leveldb_options_t;
    extern fn leveldb_options_destroy(options: *leveldb_options_t) void;
    extern fn leveldb_options_set_create_if_missing(options: *leveldb_options_t, val: u8) void;
    extern fn leveldb_readoptions_create() ?*leveldb_readoptions_t;
    extern fn leveldb_readoptions_destroy(options: *leveldb_readoptions_t) void;
    extern fn leveldb_writeoptions_create() ?*leveldb_writeoptions_t;
    extern fn leveldb_writeoptions_destroy(options: *leveldb_writeoptions_t) void;
    extern fn leveldb_create_iterator(db: *leveldb_t, options: *leveldb_readoptions_t) ?*leveldb_iterator_t;
    extern fn leveldb_iter_destroy(it: *leveldb_iterator_t) void;
    extern fn leveldb_iter_valid(it: *const leveldb_iterator_t) u8;
    extern fn leveldb_iter_seek_to_first(it: *leveldb_iterator_t) void;
    extern fn leveldb_iter_seek_to_last(it: *leveldb_iterator_t) void;
    extern fn leveldb_iter_seek(it: *leveldb_iterator_t, k: [*]const u8, klen: usize) void;
    extern fn leveldb_iter_next(it: *leveldb_iterator_t) void;
    extern fn leveldb_iter_prev(it: *leveldb_iterator_t) void;
    extern fn leveldb_iter_key(it: *const leveldb_iterator_t, klen: *usize) [*]const u8;
    extern fn leveldb_iter_value(it: *const leveldb_iterator_t, vlen: *usize) [*]const u8;
    extern fn leveldb_iter_get_error(it: *const leveldb_iterator_t, errptr: *?[*:0]u8) void;
    extern fn leveldb_writebatch_create() ?*leveldb_writebatch_t;
    extern fn leveldb_writebatch_destroy(batch: *leveldb_writebatch_t) void;
    extern fn leveldb_writebatch_put(batch: *leveldb_writebatch_t, key: [*]const u8, klen: usize, val: [*]const u8, vlen: usize) void;
    extern fn leveldb_writebatch_delete(batch: *leveldb_writebatch_t, key: [*]const u8, klen: usize) void;
    extern fn leveldb_writebatch_clear(batch: *leveldb_writebatch_t) void;
    extern fn leveldb_free(ptr: ?*anyopaque) void;

    const leveldb_t = opaque {};
    const leveldb_options_t = opaque {};
    const leveldb_readoptions_t = opaque {};
    const leveldb_writeoptions_t = opaque {};
    const leveldb_iterator_t = opaque {};
    const leveldb_writebatch_t = opaque {};
};

pub const DB = struct {
    handle: *c.leveldb_t,
    read_opts: *c.leveldb_readoptions_t,
    write_opts: *c.leveldb_writeoptions_t,

    pub fn open(path: [*:0]const u8, create_if_missing: bool) !DB {
        const opts = c.leveldb_options_create() orelse return error.Failed;
        defer c.leveldb_options_destroy(opts);
        c.leveldb_options_set_create_if_missing(opts, @intFromBool(create_if_missing));

        var err: ?[*:0]u8 = null;
        const handle = c.leveldb_open(opts, path, &err);
        if (err) |e| {
            c.leveldb_free(e);
            return error.Failed;
        }
        const ro = c.leveldb_readoptions_create() orelse return error.Failed;
        const wo = c.leveldb_writeoptions_create() orelse return error.Failed;
        return .{ .handle = handle orelse return error.Failed, .read_opts = ro, .write_opts = wo };
    }

    pub fn close(self: *DB) void {
        c.leveldb_readoptions_destroy(self.read_opts);
        c.leveldb_writeoptions_destroy(self.write_opts);
        c.leveldb_close(self.handle);
    }

    pub fn put(self: *DB, key: []const u8, value: []const u8) !void {
        var err: ?[*:0]u8 = null;
        c.leveldb_put(self.handle, self.write_opts, key.ptr, key.len, value.ptr, value.len, &err);
        if (err) |e| {
            c.leveldb_free(e);
            return error.Failed;
        }
    }

    pub fn get(self: *DB, key: []const u8) ?[]const u8 {
        var vallen: usize = 0;
        var err: ?[*:0]u8 = null;
        const val = c.leveldb_get(self.handle, self.read_opts, key.ptr, key.len, &vallen, &err);
        if (err) |e| {
            c.leveldb_free(e);
            return null;
        }
        if (val == null) return null;
        return val.?[0..vallen];
    }

    pub fn freeValue(value: []const u8) void {
        c.leveldb_free(@ptrCast(@constCast(value.ptr)));
    }

    pub fn delete(self: *DB, key: []const u8) !void {
        var err: ?[*:0]u8 = null;
        c.leveldb_delete(self.handle, self.write_opts, key.ptr, key.len, &err);
        if (err) |e| {
            c.leveldb_free(e);
            return error.Failed;
        }
    }

    pub fn iterator(self: *DB) Iterator {
        const it = c.leveldb_create_iterator(self.handle, self.read_opts);
        return .{ .handle = it.? };
    }
};

pub const WriteBatch = struct {
    handle: *c.leveldb_writebatch_t,

    pub fn init() !WriteBatch {
        return .{ .handle = c.leveldb_writebatch_create() orelse return error.Failed };
    }

    pub fn deinit(self: *WriteBatch) void {
        c.leveldb_writebatch_destroy(self.handle);
    }

    pub fn put(self: *WriteBatch, key: []const u8, value: []const u8) void {
        c.leveldb_writebatch_put(self.handle, key.ptr, key.len, value.ptr, value.len);
    }

    pub fn delete(self: *WriteBatch, key: []const u8) void {
        c.leveldb_writebatch_delete(self.handle, key.ptr, key.len);
    }

    pub fn clear(self: *WriteBatch) void {
        c.leveldb_writebatch_clear(self.handle);
    }

    pub fn write(self: *WriteBatch, db: *DB) !void {
        var err: ?[*:0]u8 = null;
        c.leveldb_write(db.handle, db.write_opts, self.handle, &err);
        if (err) |e| {
            c.leveldb_free(e);
            return error.Failed;
        }
    }
};

pub const Iterator = struct {
    handle: *c.leveldb_iterator_t,

    pub fn deinit(self: *Iterator) void {
        c.leveldb_iter_destroy(self.handle);
    }

    pub fn valid(self: *const Iterator) bool {
        return c.leveldb_iter_valid(self.handle) != 0;
    }

    pub fn seekToFirst(self: *Iterator) void {
        c.leveldb_iter_seek_to_first(self.handle);
    }

    pub fn seekToLast(self: *Iterator) void {
        c.leveldb_iter_seek_to_last(self.handle);
    }

    pub fn seek(self: *Iterator, target: []const u8) void {
        c.leveldb_iter_seek(self.handle, target.ptr, target.len);
    }

    pub fn next(self: *Iterator) void {
        c.leveldb_iter_next(self.handle);
    }

    pub fn prev(self: *Iterator) void {
        c.leveldb_iter_prev(self.handle);
    }

    pub fn key(self: *const Iterator) []const u8 {
        var len: usize = 0;
        const k = c.leveldb_iter_key(self.handle, &len);
        return k[0..len];
    }

    pub fn value(self: *const Iterator) []const u8 {
        var len: usize = 0;
        const v = c.leveldb_iter_value(self.handle, &len);
        return v[0..len];
    }

    pub fn getError(self: *const Iterator) ?[*:0]const u8 {
        var err: ?[*:0]u8 = null;
        c.leveldb_iter_get_error(self.handle, &err);
        return if (err) |e| @ptrCast(e) else null;
    }
};
