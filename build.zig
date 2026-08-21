const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const algebra_dep = b.dependency("zig_algebra", .{
        .target = target,
        .optimize = optimize,
    });

    // Module for transcript library
    const transcript_mod = b.addModule("zig-transcript", .{
        .root_source_file = b.path("libs/transcript/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    transcript_mod.addImport("zig-algebra-traits", algebra_dep.module("zig-algebra-traits"));
    transcript_mod.addImport("zig-hash", algebra_dep.module("zig-hash"));
    transcript_mod.addImport("zig-rng", algebra_dep.module("zig-rng"));

    // Module for commitment library
    const commitment_mod = b.addModule("zig-commitment", .{
        .root_source_file = b.path("libs/commitment/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    commitment_mod.addImport("zig-algebra-traits", algebra_dep.module("zig-algebra-traits"));
    commitment_mod.addImport("zig-field", algebra_dep.module("zig-field"));
    commitment_mod.addImport("zig-merkle", algebra_dep.module("zig-merkle"));
    commitment_mod.addImport("zig-poly", algebra_dep.module("zig-poly"));

    // Module for air library
    const air_mod = b.addModule("zig-air", .{
        .root_source_file = b.path("libs/air/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    air_mod.addImport("zig-algebra-traits", algebra_dep.module("zig-algebra-traits"));

    // Test step that runs all library tests
    const test_step = b.step("test", "Run all tests");
    
    // Transcript tests
    const transcript_test_module = b.createModule(.{
        .root_source_file = b.path("libs/transcript/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    transcript_test_module.addImport("zig-algebra-traits", algebra_dep.module("zig-algebra-traits"));
    transcript_test_module.addImport("zig-hash", algebra_dep.module("zig-hash"));
    transcript_test_module.addImport("zig-rng", algebra_dep.module("zig-rng"));
    const transcript_tests = b.addTest(.{
        .name = "zig-transcript-tests",
        .root_module = transcript_test_module,
    });
    test_step.dependOn(&transcript_tests.step);

    // Commitment tests
    const commitment_test_module = b.createModule(.{
        .root_source_file = b.path("libs/commitment/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    commitment_test_module.addImport("zig-algebra-traits", algebra_dep.module("zig-algebra-traits"));
    commitment_test_module.addImport("zig-field", algebra_dep.module("zig-field"));
    commitment_test_module.addImport("zig-merkle", algebra_dep.module("zig-merkle"));
    commitment_test_module.addImport("zig-poly", algebra_dep.module("zig-poly"));
    const commitment_tests = b.addTest(.{
        .name = "zig-commitment-tests",
        .root_module = commitment_test_module,
    });
    test_step.dependOn(&commitment_tests.step);

    // Air tests
    const air_test_module = b.createModule(.{
        .root_source_file = b.path("libs/air/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    air_test_module.addImport("zig-algebra-traits", algebra_dep.module("zig-algebra-traits"));
    const air_tests = b.addTest(.{
        .name = "zig-air-tests",
        .root_module = air_test_module,
    });
    test_step.dependOn(&air_tests.step);
}
