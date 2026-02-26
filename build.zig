const std = @import("std");

const leveldb_sources = &[_][]const u8{
    "db/builder.cc",
    "db/c.cc",
    "db/db_impl.cc",
    "db/db_iter.cc",
    "db/dbformat.cc",
    "db/dumpfile.cc",
    "db/filename.cc",
    "db/log_reader.cc",
    "db/log_writer.cc",
    "db/memtable.cc",
    "db/repair.cc",
    "db/table_cache.cc",
    "db/version_edit.cc",
    "db/version_set.cc",
    "db/write_batch.cc",
    "table/block_builder.cc",
    "table/block.cc",
    "table/filter_block.cc",
    "table/format.cc",
    "table/iterator.cc",
    "table/merger.cc",
    "table/table_builder.cc",
    "table/table.cc",
    "table/two_level_iterator.cc",
    "util/arena.cc",
    "util/bloom.cc",
    "util/cache.cc",
    "util/coding.cc",
    "util/comparator.cc",
    "util/crc32c.cc",
    "util/env.cc",
    "util/filter_policy.cc",
    "util/hash.cc",
    "util/logging.cc",
    "util/options.cc",
    "util/status.cc",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zignet_dep = b.dependency("ZigNet", .{});
    const raknet_mod = zignet_dep.module("Raknet");

    const binarystream_dep = b.dependency("BinaryStream", .{});
    const binarystream_mod = binarystream_dep.module("BinaryStream");

    const zlib_dep = b.dependency("zlib", .{
        .target = target,
        .optimize = optimize,
    });

    const is_windows = target.result.os.tag == .windows;

    const leveldb_lib = b.addLibrary(.{
        .name = "leveldb",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    leveldb_lib.addIncludePath(b.path("dump/leveldb-src"));
    leveldb_lib.addIncludePath(b.path("dump/leveldb-src/include"));
    leveldb_lib.linkLibCpp();
    leveldb_lib.linkLibrary(zlib_dep.artifact("z"));

    const platform_flags: []const []const u8 = if (is_windows)
        &.{ "-std=c++17", "-DLEVELDB_PLATFORM_WINDOWS", "-D_UNICODE", "-DUNICODE", "-DWIN32_LEAN_AND_MEAN", "-DNOMINMAX" }
    else
        &.{ "-std=c++17", "-DLEVELDB_PLATFORM_POSIX", "-DHAVE_FDATASYNC=1", "-DHAVE_O_CLOEXEC=1" };

    for (leveldb_sources) |src| {
        leveldb_lib.addCSourceFile(.{ .file = b.path(b.fmt("dump/leveldb-src/{s}", .{src})), .flags = platform_flags });
    }

    const env_file: []const u8 = if (is_windows) "util/env_windows.cc" else "util/env_posix.cc";
    leveldb_lib.addCSourceFile(.{ .file = b.path(b.fmt("dump/leveldb-src/{s}", .{env_file})), .flags = platform_flags });

    const nbt_mod = b.addModule("nbt", .{
        .root_source_file = b.path("src/nbt/root.zig"),
        .target = target,
    });
    nbt_mod.addImport("BinaryStream", binarystream_mod);

    const protocol_mod = b.addModule("protocol", .{
        .root_source_file = b.path("src/protocol/root.zig"),
        .target = target,
    });
    protocol_mod.addImport("BinaryStream", binarystream_mod);
    protocol_mod.addImport("nbt", nbt_mod);

    const leveldb_mod = b.addModule("leveldb", .{
        .root_source_file = b.path("libs/leveldb/leveldb.zig"),
        .target = target,
    });

    const conduit_mod = b.addModule("conduit", .{
        .root_source_file = b.path("src/conduit/root.zig"),
        .target = target,
    });
    conduit_mod.addImport("BinaryStream", binarystream_mod);
    conduit_mod.addImport("Raknet", raknet_mod);
    conduit_mod.addImport("protocol", protocol_mod);
    conduit_mod.addImport("nbt", nbt_mod);
    conduit_mod.addImport("leveldb", leveldb_mod);
    conduit_mod.linkLibrary(zlib_dep.artifact("z"));
    if (is_windows) {
        conduit_mod.linkSystemLibrary("psapi", .{});
    }

    const exe = b.addExecutable(.{
        .name = "Conduit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "conduit", .module = conduit_mod },
                .{ .name = "protocol", .module = protocol_mod },
                .{ .name = "nbt", .module = nbt_mod },
                .{ .name = "leveldb", .module = leveldb_mod },
            },
        }),
    });

    exe.linkLibrary(zlib_dep.artifact("z"));
    exe.linkLibrary(leveldb_lib);
    exe.linkLibCpp();

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
