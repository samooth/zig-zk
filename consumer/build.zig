//! A consumer of zig-zk that only ever touches the public API.
//!
//! This exists because the test suite could not tell whether the library was
//! usable. Every test in this repository lives inside the module it tests, where
//! a `const` is visible to the test and invisible to everyone else, so five
//! things were wrong for a consumer and green for the suite: `Circuit` was not
//! `pub`, `shamir.split` only compiled against a test-local scalar,
//! `squeezeField` read a field that does not exist, the quick start reused one
//! channel and so verified as `false`, and `Schnorr.fromBytes` took a shape no
//! real field has.
//!
//! It is an executable, not a test, so that `zig build` in this directory is
//! the thing a stranger runs. It gets exactly five modules and nothing else: no
//! relative import can reach a file, because no file is on its search path.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stark = b.dependency("zig_stark", .{ .target = target, .optimize = optimize });
    const snark = b.dependency("zig_snark", .{ .target = target, .optimize = optimize });
    const transcript = b.dependency("zig_transcript", .{ .target = target, .optimize = optimize });
    const commitment = b.dependency("zig_commitment", .{ .target = target, .optimize = optimize });
    const signature = b.dependency("zig_signature", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-commitment", .module = commitment.module("zig-commitment") },
                .{ .name = "zig-signature", .module = signature.module("zig-signature") },
                .{ .name = "zig-snark", .module = snark.module("zig-snark") },
                .{ .name = "zig-stark", .module = stark.module("zig-stark") },
                .{ .name = "zig-transcript", .module = transcript.module("zig-transcript") },
            },
        }),
    });

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);

    const run_step = b.step("run", "Build and run the consumer");
    run_step.dependOn(&run.step);

    // The gate: building this directory is the check. Nothing else in the
    // repository asserts that the public API can be called.
    b.getInstallStep().dependOn(&exe.step);
}
