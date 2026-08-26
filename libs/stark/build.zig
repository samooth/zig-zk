const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module for the stark library (M31 + Binius stacks).
    // Uses zig-transcript for the Fiat-Shamir channel.
    const transcript_dep = b.dependency("zig_transcript", .{
        .target = target,
        .optimize = optimize,
    });
    const transcript_mod = transcript_dep.module("zig-transcript");

    const algebra_dep = b.dependency("zig_algebra", .{
        .target = target,
        .optimize = optimize,
    });
    const field_mod = algebra_dep.module("zig-field");

    const stark_mod = b.addModule("zig-stark", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stark_mod.addImport("zig-transcript", transcript_mod);
    stark_mod.addImport("zig-field", field_mod);

    const test_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zig-transcript", transcript_mod);
    test_module.addImport("zig-field", field_mod);
    const tests = b.addTest(.{
        .name = "zig-stark-tests",
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
