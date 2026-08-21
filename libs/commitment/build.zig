const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const traits_dep = b.dependency("zig_algebra_traits", .{
        .target = target,
        .optimize = optimize,
    });
    const traits_mod = traits_dep.module("zig-algebra-traits");

    const field_dep = b.dependency("zig_field", .{
        .target = target,
        .optimize = optimize,
    });
    const field_mod = field_dep.module("zig-field");

    const merkle_dep = b.dependency("zig_merkle", .{
        .target = target,
        .optimize = optimize,
    });
    const merkle_mod = merkle_dep.module("zig-merkle");

    const poly_dep = b.dependency("zig_poly", .{
        .target = target,
        .optimize = optimize,
    });
    const poly_mod = poly_dep.module("zig-poly");

    const commitment_mod = b.addModule("zig-commitment", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    commitment_mod.addImport("zig-algebra-traits", traits_mod);
    commitment_mod.addImport("zig-field", field_mod);
    commitment_mod.addImport("zig-merkle", merkle_mod);
    commitment_mod.addImport("zig-poly", poly_mod);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zig-algebra-traits", traits_mod);
    test_module.addImport("zig-field", field_mod);
    test_module.addImport("zig-merkle", merkle_mod);
    test_module.addImport("zig-poly", poly_mod);
    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
