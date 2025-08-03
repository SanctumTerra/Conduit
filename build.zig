const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Conduit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ws2_32"); // For windows sockets.
    }

    const binarystream_dep = b.dependency("BinaryStream", .{});
    exe.root_module.addImport("BinaryStream", binarystream_dep.module("BinaryStream"));

    const zignet_dep = b.dependency("ZigNet", .{});
    exe.root_module.addImport("ZigNet", zignet_dep.module("Raknet"));

    const CAllocator = b.createModule(.{
        .root_source_file = b.path("libs/CAllocator.zig"),
    });
    exe.root_module.addImport("CAllocator", CAllocator);

    const Logger = b.createModule(.{
        .root_source_file = b.path("libs/Logger.zig"),
    });
    exe.root_module.addImport("Logger", Logger);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
