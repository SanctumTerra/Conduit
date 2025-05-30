const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    setup_imports(b, exe_mod, target, optimize);

    const exe = b.addExecutable(.{
        .name = "Conduit",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
    exe.linkLibC();

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

pub fn setup_imports(b: *std.Build, exe_mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const allocator_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/Allocator.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("CAllocator", allocator_mod);
    const logger_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/Logger.zig"),
        .target = target,
        .optimize = optimize,
    });
    logger_mod.addImport("CAllocator", allocator_mod);

    exe_mod.addImport("Logger", logger_mod);

    const binary_stream_mod = b.createModule(.{
        .root_source_file = b.path("src/stream/BinaryStream.zig"),
        .target = target,
        .optimize = optimize,
    });
    binary_stream_mod.addImport("CAllocator", allocator_mod);
    binary_stream_mod.addImport("Logger", logger_mod);

    exe_mod.addImport("BinaryStream", binary_stream_mod);
}
