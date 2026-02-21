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

    const data_mod = b.addModule("data", .{
        .root_source_file = b.path("src/data/root.zig"),
        .target = target,
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
    protocol_mod.addImport("data", data_mod);

    const conduit_mod = b.addModule("conduit", .{
        .root_source_file = b.path("src/conduit/root.zig"),
        .target = target,
    });
    conduit_mod.addImport("BinaryStream", binarystream_mod);
    conduit_mod.addImport("Raknet", raknet_mod);
    conduit_mod.addImport("protocol", protocol_mod);
    conduit_mod.addImport("nbt", nbt_mod);
    conduit_mod.addImport("data", data_mod);
    conduit_mod.linkLibrary(zlib_dep.artifact("z"));

    const exe = b.addExecutable(.{
        .name = "ConduitV2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "conduit", .module = conduit_mod },
                .{ .name = "protocol", .module = protocol_mod },
                .{ .name = "nbt", .module = nbt_mod },
                .{ .name = "data", .module = data_mod },
            },
        }),
    });

    exe.linkLibrary(zlib_dep.artifact("z"));

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
