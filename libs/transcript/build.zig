const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const algebra_dep = b.dependency("zig_algebra", .{
        .target = target,
        .optimize = optimize,
    });
    const traits_mod = algebra_dep.module("zig-algebra-traits");
    const hash_mod = algebra_dep.module("zig-hash");

    const transcript_mod = b.addModule("zig-transcript", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    transcript_mod.addImport("zig-algebra-traits", traits_mod);
    transcript_mod.addImport("zig-hash", hash_mod);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zig-algebra-traits", traits_mod);
    test_module.addImport("zig-hash", hash_mod);
    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
