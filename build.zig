const std = @import("std");

const Import = struct {
    name: []const u8,
    module: *std.Build.Module,
};

fn addTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    comptime name: []const u8,
    root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const Import,
) void {
    const mod = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    for (imports) |imp| mod.addImport(imp.name, imp.module);
    const tests = b.addTest(.{
        .name = name,
        .root_module = mod,
    });
    const run = b.addRunArtifact(tests);
    test_step.dependOn(&run.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const algebra_dep = b.dependency("zig_algebra", .{
        .target = target,
        .optimize = optimize,
    });

    const traits = algebra_dep.module("zig-algebra-traits");
    const hash = algebra_dep.module("zig-hash");
    const rng = algebra_dep.module("zig-rng");
    const field = algebra_dep.module("zig-field");
    const curve = algebra_dep.module("zig-curve");
    const merkle = algebra_dep.module("zig-merkle");
    const poly = algebra_dep.module("zig-poly");

    // Module for transcript library
    const transcript_mod = b.addModule("zig-transcript", .{
        .root_source_file = b.path("libs/transcript/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    transcript_mod.addImport("zig-algebra-traits", traits);
    transcript_mod.addImport("zig-hash", hash);
    transcript_mod.addImport("zig-rng", rng);

    // Module for commitment library
    const commitment_mod = b.addModule("zig-commitment", .{
        .root_source_file = b.path("libs/commitment/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    commitment_mod.addImport("zig-algebra-traits", traits);
    commitment_mod.addImport("zig-field", field);
    commitment_mod.addImport("zig-merkle", merkle);
    commitment_mod.addImport("zig-poly", poly);

    // Module for air library
    const air_mod = b.addModule("zig-air", .{
        .root_source_file = b.path("libs/air/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    air_mod.addImport("zig-algebra-traits", traits);

    // Module for signature library
    const signature_mod = b.addModule("zig-signature", .{
        .root_source_file = b.path("libs/signature/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    signature_mod.addImport("zig-algebra-traits", traits);
    signature_mod.addImport("zig-curve", curve);
    signature_mod.addImport("zig-hash", hash);
    signature_mod.addImport("zig-rng", rng);

    // Module for stark library (M31 + Binius stacks; uses zig-transcript)
    const stark_mod = b.addModule("zig-stark", .{
        .root_source_file = b.path("libs/stark/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stark_mod.addImport("zig-transcript", transcript_mod);
    stark_mod.addImport("zig-field", field);

    // Test step that runs all library tests
    const test_step = b.step("test", "Run all tests");

    addTests(b, test_step, "zig-transcript-tests", b.path("libs/transcript/src/root.zig"), target, optimize, &.{
        .{ .name = "zig-algebra-traits", .module = traits },
        .{ .name = "zig-hash", .module = hash },
        .{ .name = "zig-rng", .module = rng },
    });
    addTests(b, test_step, "zig-commitment-tests", b.path("libs/commitment/src/root.zig"), target, optimize, &.{
        .{ .name = "zig-algebra-traits", .module = traits },
        .{ .name = "zig-field", .module = field },
        .{ .name = "zig-merkle", .module = merkle },
        .{ .name = "zig-poly", .module = poly },
    });
    addTests(b, test_step, "zig-air-tests", b.path("libs/air/src/root.zig"), target, optimize, &.{
        .{ .name = "zig-algebra-traits", .module = traits },
    });
    addTests(b, test_step, "zig-signature-tests", b.path("libs/signature/src/root.zig"), target, optimize, &.{
        .{ .name = "zig-algebra-traits", .module = traits },
        .{ .name = "zig-curve", .module = curve },
        .{ .name = "zig-hash", .module = hash },
        .{ .name = "zig-rng", .module = rng },
    });
    addTests(b, test_step, "zig-stark-tests", b.path("libs/stark/root.zig"), target, optimize, &.{
        .{ .name = "zig-field", .module = field },
        .{ .name = "zig-transcript", .module = transcript_mod },
    });
}
