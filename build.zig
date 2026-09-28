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
    const binary_field = algebra_dep.module("zig-binary-field");
    const curve = algebra_dep.module("zig-curve");
    const merkle = algebra_dep.module("zig-merkle");
    const parallel = algebra_dep.module("zig-parallel");
    const poly = algebra_dep.module("zig-poly");
    const pairing = algebra_dep.module("zig-pairing");

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

    // Module for snark library (Groth16 verifier; uses pairing)
    const snark_mod = b.addModule("zig-snark", .{
        .root_source_file = b.path("libs/snark/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    snark_mod.addImport("zig-curve", curve);
    snark_mod.addImport("zig-pairing", pairing);

    // Module for stark library (M31 + Binius stacks; uses zig-transcript)
    const stark_mod = b.addModule("zig-stark", .{
        .root_source_file = b.path("libs/stark/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stark_mod.addImport("zig-transcript", transcript_mod);
    stark_mod.addImport("zig-field", field);
    // The binary-field layer is consumed from zig-algebra, not vendored: the
    // binius zone adopted field, tower, pack, polynomial and clmul from 0.5.1.
    stark_mod.addImport("zig-binary-field", binary_field);

    // Documentation invariants: every markdown file is paired across the two
    // languages, declares its language, and has not mixed the two.
    const docs_check = b.addExecutable(.{
        .name = "check-docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check_docs.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_docs_check = b.addRunArtifact(docs_check);
    // Both gates locate the repository by walking from their working directory,
    // so the working directory is theirs to guarantee and not to inherit. Without
    // this, a run step that starts anywhere else reports a gate that found no
    // sources: the contract gate fails with every zone at zero, and the docs
    // gate passes on whatever handful of files it happened to see.
    run_docs_check.setCwd(b.path("."));
    const docs_step = b.step("check-docs", "Verify the documentation is paired and monolingual");
    docs_step.dependOn(&run_docs_check.step);

    // Cross-repository contract with the pinned zig-algebra: the divergence
    // ledger, the import boundary, and the pin itself. See
    // scripts/check_contract.zig for what each rule is protecting.
    const contract_check = b.addExecutable(.{
        .name = "check-contract",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check_contract.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_contract_check = b.addRunArtifact(contract_check);
    run_contract_check.setCwd(b.path("."));
    const contract_step = b.step("check-contract", "Verify the declared contract with zig-algebra");
    contract_step.dependOn(&run_contract_check.step);

    // Test step that runs all library tests
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_docs_check.step);
    test_step.dependOn(&run_contract_check.step);

    // The gate is the conformance check, so the gate's own scanner gets tested.
    // Test blocks in a file that is only ever built as an executable never run,
    // which is the same mistake this gate exists to make visible.
    const contract_tests = b.addTest(.{
        .name = "check-contract-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check_contract.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(contract_tests).step);

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
    addTests(b, test_step, "zig-signature-tests", b.path("libs/signature/src/root.zig"), target, optimize, &.{
        .{ .name = "zig-algebra-traits", .module = traits },
        .{ .name = "zig-curve", .module = curve },
        .{ .name = "zig-hash", .module = hash },
        .{ .name = "zig-rng", .module = rng },
    });
    addTests(b, test_step, "zig-stark-tests", b.path("libs/stark/root.zig"), target, optimize, &.{
        .{ .name = "zig-field", .module = field },
        .{ .name = "zig-transcript", .module = transcript_mod },
        .{ .name = "zig-binary-field", .module = binary_field },
        .{ .name = "zig-parallel", .module = parallel },
    });
    addTests(b, test_step, "zig-snark-tests", b.path("libs/snark/src/root.zig"), target, optimize, &.{
        .{ .name = "zig-field", .module = field },
        .{ .name = "zig-curve", .module = curve },
        .{ .name = "zig-pairing", .module = pairing },
    });

    // End-to-end and fuzz suites (canonical zig-stark tests).
    const stark_lib_mod = b.addModule("zig-stark-e2e-src", .{
        .root_source_file = b.path("libs/stark/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-field", .module = field },
            .{ .name = "zig-transcript", .module = transcript_mod },
            .{ .name = "zig-binary-field", .module = binary_field },
            // The parallel pool is consumed from zig-algebra: the sum-check that
            // takes it is upstream's, and it takes that type, not ours.
            .{ .name = "zig-parallel", .module = parallel },
        },
    });

    // Guards on the binary-field layer we consume from zig-algebra rather than
    // own: a module's test blocks do not run in a consumer, and the identity
    // that matters can only be witnessed over a prime.
    const field_layer_mod = b.createModule(.{
        .root_source_file = b.path("libs/stark/tests/field_layer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-binary-field", .module = binary_field },
            .{ .name = "zig-field", .module = field },
        },
    });
    const field_layer_tests = b.addTest(.{ .name = "zig-stark-field-layer-tests", .root_module = field_layer_mod });
    test_step.dependOn(&b.addRunArtifact(field_layer_tests).step);

    // Known-answer tests for the adopted Merkle commitment's leaf convention.
    const merkle_kat_mod = b.createModule(.{
        .root_source_file = b.path("libs/stark/tests/merkle_kat.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-binary-field", .module = binary_field },
        },
    });
    const merkle_kat_tests = b.addTest(.{ .name = "zig-stark-merkle-kat-tests", .root_module = merkle_kat_mod });
    test_step.dependOn(&b.addRunArtifact(merkle_kat_tests).step);

    const e2e_mod = b.createModule(.{
        .root_source_file = b.path("libs/stark/tests/e2e_tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-stark", .module = stark_lib_mod },
            .{ .name = "zig-transcript", .module = transcript_mod },
            .{ .name = "zig-parallel", .module = parallel },
            .{ .name = "zig-field", .module = field },
        },
    });
    const e2e_tests = b.addTest(.{ .name = "zig-stark-e2e-tests", .root_module = e2e_mod });
    test_step.dependOn(&b.addRunArtifact(e2e_tests).step);

    // The gadget fuzz is 2000 rounds by default, which is about three minutes.
    // The knob exists so a quick local run is possible without pretending the
    // short run is the full one.
    const fuzz_opts = b.addOptions();
    fuzz_opts.addOption(usize, "iters", b.option(
        usize,
        "fuzz-iters",
        "Rounds of the Binius gadget fuzz suite (default 2000)",
    ) orelse 2000);
    const fuzz_mod = b.createModule(.{
        .root_source_file = b.path("libs/stark/tests/fuzz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-stark", .module = stark_lib_mod },
            .{ .name = "zig-field", .module = field },
            .{ .name = "zig-parallel", .module = parallel },
        },
    });
    fuzz_mod.addOptions("fuzz_options", fuzz_opts);
    const fuzz_tests = b.addTest(.{ .name = "zig-stark-fuzz-tests", .root_module = fuzz_mod });
    test_step.dependOn(&b.addRunArtifact(fuzz_tests).step);
}
