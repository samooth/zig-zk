const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const algebra_dep = b.dependency("zig_algebra", .{
        .target = target,
        .optimize = optimize,
    });
    const curve_mod = algebra_dep.module("zig-curve");
    const pairing_mod = algebra_dep.module("zig-pairing");

    const snark_mod = b.addModule("zig-snark", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    snark_mod.addImport("zig-curve", curve_mod);
    snark_mod.addImport("zig-pairing", pairing_mod);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zig-curve", curve_mod);
    test_module.addImport("zig-pairing", pairing_mod);
    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
