const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const traits_dep = b.dependency("zig_algebra_traits", .{
        .target = target,
        .optimize = optimize,
    });
    const traits_mod = traits_dep.module("zig-algebra-traits");

    const hash_dep = b.dependency("zig_hash", .{
        .target = target,
        .optimize = optimize,
    });
    const hash_mod = hash_dep.module("zig-hash");

    const rng_dep = b.dependency("zig_rng", .{
        .target = target,
        .optimize = optimize,
    });
    const rng_mod = rng_dep.module("zig-rng");

    const transcript_mod = b.addModule("zig-transcript", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    transcript_mod.addImport("zig-algebra-traits", traits_mod);
    transcript_mod.addImport("zig-hash", hash_mod);
    transcript_mod.addImport("zig-rng", rng_mod);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zig-algebra-traits", traits_mod);
    test_module.addImport("zig-hash", hash_mod);
    test_module.addImport("zig-rng", rng_mod);
    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
