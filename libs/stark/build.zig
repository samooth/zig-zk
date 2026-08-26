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

    // End-to-end and fuzz suites (ported from zig-stark/tests).
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("tests/e2e_tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-stark", .module = stark_mod },
            .{ .name = "zig-transcript", .module = transcript_mod },
            .{ .name = "zig-field", .module = field_mod },
        },
    });
    const e2e_tests = b.addTest(.{
        .name = "zig-stark-e2e-tests",
        .root_module = e2e_module,
    });
    const run_e2e = b.addRunArtifact(e2e_tests);
    test_step.dependOn(&run_e2e.step);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-stark", .module = stark_mod },
            .{ .name = "zig-field", .module = field_mod },
        },
    });
    const fuzz_tests = b.addTest(.{
        .name = "zig-stark-fuzz-tests",
        .root_module = fuzz_module,
    });
    const run_fuzz = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz.step);
}
