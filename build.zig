const std = @import("std");

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
    if (target.result.os.tag == .windows) {
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
    exe.addLibraryPath(b.path("libs/leveldb/lib"));
    exe.linkSystemLibrary("leveldb");
    exe.linkLibCpp();

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const db_inspect = b.addExecutable(.{
        .name = "db-inspect",
        .root_module = b.createModule(.{
            .root_source_file = b.path("dump/db-inspect.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "leveldb", .module = leveldb_mod },
            },
        }),
    });
    db_inspect.addLibraryPath(b.path("libs/leveldb/lib"));
    db_inspect.linkSystemLibrary("leveldb");
    db_inspect.linkLibrary(zlib_dep.artifact("z"));
    db_inspect.linkLibCpp();
    b.installArtifact(db_inspect);

    const inspect_step = b.step("inspect", "Run db-inspect");
    const inspect_cmd = b.addRunArtifact(db_inspect);
    inspect_step.dependOn(&inspect_cmd.step);
    if (b.args) |args| {
        inspect_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
