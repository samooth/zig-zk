//! Randomized property stress for the Binius gadgets. Every iteration:
//!   - builds a random valid witness, proves and verifies it (must accept), and
//!   - tampers a byte of the *serialized proof* and verifies again (must
//!     reject — the verifier's sum-check / Merkle checks are exact, so a
//!     modified proof is rejected deterministically, unlike a witness tamper
//!     whose zero-check can miss a single-point violation in a small field).
//! Runs under the leak-checking DebugAllocator, as part of `zig build test`.
//!
//! Two field pairs, and the second one exists for a reason that is not
//! thoroughness. The quick suite is single-field over `Gf256`, chosen for
//! speed, and a sum-check over an eight-bit field has a soundness error of order
//! 1/|F|, and the rounds' errors add rather than compound -- a sum bound of
//! order k/|F| for k rounds, not a product. What it stresses is the plumbing,
//! the witness shapes and the tamper rejection, and it says nothing about
//! soundness.
//! The wide suite runs the same gadgets with a 128-bit extension, where the
//! prover is the one production instantiation uses (`BiniusStark(Gf16, Gf2_128)`,
//! which the end-to-end tests also run), and it is what puts random witnesses
//! through that width. It runs far fewer rounds, because a 128-bit tower
//! product is a software fallback the repository already records as slow at
//! `tests/e2e_tests.zig`, where a Debug build avoids it for that reason.
//!
//! The bound is a sum, not a product: a round's error is of order 1/|F| and
//! k rounds give order k/|F|, so an eight-bit extension is paid for once per
//! round and no round count rescues it. `k` belongs to the caller: the prover
//! runs exactly that many sum-check rounds, the verifier checks the count, and
//! the count does not depend on the field. The field is what binds: one round
//! over eight bits costs 2^-8. And Binius commits in a bilinear algebra rather
//! than a field, so a prime-field soundness argument does not carry over
//! verbatim.
//!
//! The claim this file can support is "the 128-bit path gets random witnesses".
//! It is not "the 128-bit path is sound", and no number of rounds would make it
//! that.

const std = @import("std");
const zs = @import("zig-stark");

const Hash = zs.hash.Hash;
const Ser = zs.core.serialization;

const FastF = zs.binius.tower.Gf256;
const FastE = zs.binius.tower.Gf256; // single-field for speed; structure is identical

// The pair the prover is instantiated over in the end-to-end suite.
const WideF = zs.binius.tower.Gf16;
const WideE = zs.binius.tower.Gf2_128;

const Rng = std.Random.DefaultPrng;

/// Prove the witness, commit the roots, and verify. Returns accept/reject.
fn proveVerify(
    comptime F: type,
    comptime E: type,
    alloc: std.mem.Allocator,
    k: usize,
    columns: []const []const F,
    constraints: anytype,
) !bool {
    const Stark = zs.binius.stark.BiniusStark(F, E);
    const CommittedPcs = zs.binius.pcs.CommittedMlePcsUnsafe(F, E);
    const roots = try alloc.alloc(Hash.Digest, columns.len);
    defer alloc.free(roots);
    for (0..columns.len) |c| {
        var tree = try CommittedPcs.commit(alloc, columns[c]);
        defer tree.deinit();
        roots[c] = tree.root();
    }
    var proof = try Stark.prove(alloc, k, columns, constraints, &.{}, "fuzz");
    defer proof.deinit(alloc);
    return try Stark.verify(alloc, k, roots, constraints, &.{}, proof, "fuzz");
}

/// The valid witness must be accepted.
fn expectAccept(comptime F: type, comptime E: type, alloc: std.mem.Allocator, k: usize, columns: []const []const F, constraints: anytype) !void {
    if (!try proveVerify(F, E, alloc, k, columns, constraints)) return error.FuzzValidRejected;
}

/// A proof with one flipped byte must be rejected (deterministic: the sum-check
/// and Merkle checks fail on any modified value).
fn expectRejectTamperedProof(comptime F: type, comptime E: type, alloc: std.mem.Allocator, k: usize, columns: []const []const F, constraints: anytype) !void {
    const Stark = zs.binius.stark.BiniusStark(F, E);
    const CommittedPcs = zs.binius.pcs.CommittedMlePcsUnsafe(F, E);
    const roots = try alloc.alloc(Hash.Digest, columns.len);
    defer alloc.free(roots);
    for (0..columns.len) |c| {
        var tree = try CommittedPcs.commit(alloc, columns[c]);
        defer tree.deinit();
        roots[c] = tree.root();
    }
    var proof = try Stark.prove(alloc, k, columns, constraints, &.{}, "fuzz");
    defer proof.deinit(alloc);

    const bytes = try Ser.serialize(alloc, proof);
    defer alloc.free(bytes);
    const tampered = try alloc.dupe(u8, bytes);
    defer alloc.free(tampered);
    tampered[bytes.len / 2] ^= 0x01;

    var rt = try Ser.deserialize(alloc, tampered, Stark.Proof);
    defer rt.deinit(alloc);
    if (try Stark.verify(alloc, k, roots, constraints, &.{}, rt, "fuzz")) return error.FuzzTamperedAccepted;
}

/// RangeCheck: valid values in [0, 2^m).
fn roundRange(comptime F: type, comptime E: type, alloc: std.mem.Allocator, rnd: std.Random) !void {
    const m = 3;
    const k = 3;
    const n: usize = @as(usize, 1) << @intCast(k);
    const RC = zs.binius.rangecheck.RangeCheck(F, E, m);

    var vals: [n]RC.UInt = undefined;
    for (&vals) |*v| v.* = @intCast(rnd.int(u8) % 8);

    const cols = try RC.generateWitness(alloc, &vals);
    defer RC.freeWitness(alloc, &cols);
    const cols_slice: []const []const F = cols[0..];

    try expectAccept(F, E, alloc, k, cols_slice, RC.constraints[0..]);
    try expectRejectTamperedProof(F, E, alloc, k, cols_slice, RC.constraints[0..]);
}

/// Compare: random pairs with x < y.
fn roundCompare(comptime F: type, comptime E: type, alloc: std.mem.Allocator, rnd: std.Random) !void {
    const m = 3;
    const k = 3;
    const n: usize = @as(usize, 1) << @intCast(k);
    const Cmp = zs.binius.compare.Compare(F, E, m);

    var x: [n]Cmp.UInt = undefined;
    var y: [n]Cmp.UInt = undefined;
    for (0..n) |i| {
        const a = rnd.int(u8) % 8;
        const b = rnd.int(u8) % 8;
        x[i] = @intCast(@min(a, b));
        y[i] = @intCast(@max(a, b));
        if (x[i] == y[i]) y[i] = @intCast(@mod(@as(u8, y[i]) + 1, 8)); // keep strictly less
    }

    const cols = try Cmp.generateWitness(alloc, &x, &y);
    defer Cmp.freeWitness(alloc, &cols);
    const cols_slice: []const []const F = cols[0..];

    try expectAccept(F, E, alloc, k, cols_slice, Cmp.constraints[0..]);
    try expectRejectTamperedProof(F, E, alloc, k, cols_slice, Cmp.constraints[0..]);
}

/// Adder: random 4-bit pairs.
fn roundAdder(comptime F: type, comptime E: type, alloc: std.mem.Allocator, rnd: std.Random) !void {
    const k = 3;
    const n: usize = @as(usize, 1) << @intCast(k);
    const Adder = zs.binius.adder.Adder(F, E);

    const x = try alloc.alloc(u4, n);
    defer alloc.free(x);
    const y = try alloc.alloc(u4, n);
    defer alloc.free(y);
    for (0..n) |i| {
        x[i] = @intCast(rnd.int(u8) % 16);
        y[i] = @intCast(rnd.int(u8) % 16);
    }

    const cols = try Adder.generateWitness(alloc, x, y);
    defer Adder.freeWitness(alloc, &cols);
    const cols_slice: []const []const F = cols[0..];

    try expectAccept(F, E, alloc, k, cols_slice, Adder.constraints[0..]);
    try expectRejectTamperedProof(F, E, alloc, k, cols_slice, Adder.constraints[0..]);
}

/// The three gadgets under one field pair. Split out so both suites below run
/// exactly the same rounds, and differ only in the field and the count.
fn runGadgets(comptime F: type, comptime E: type, alloc: std.mem.Allocator, rnd: std.Random, rounds: usize) !void {
    for (0..rounds) |_| {
        try roundRange(F, E, alloc, rnd);
        try roundCompare(F, E, alloc, rnd);
        try roundAdder(F, E, alloc, rnd);
    }
}

test "binius gadgets: randomised accept, and reject a tampered proof" {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const check = gpa.deinit();
        if (check != .ok) @panic("fuzz: memory leaks detected");
    }

    const iters = @import("fuzz_options").iters;
    var prng = Rng.init(0x5eed_c0de);
    const rnd = prng.random();

    try runGadgets(FastF, FastE, alloc, rnd, iters);
}

test "binius gadgets over a 128-bit extension: the same rounds, random witnesses" {
    // The claim this makes is narrow and is the one the ledger records: the
    // 128-bit path gets random witnesses. It is not a soundness claim. The
    // default is over Gf256, which is eight bits wide, and a sum-check there has
    // a per-round soundness error of order 1/|F| whose rounds add, giving
    // order k/|F| for k rounds -- so the quick suite above is plumbing coverage,
    // and this is the part that puts the same gadgets through the width the
    // prover actually uses. k belongs to the caller, not to the prover.
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const check = gpa.deinit();
        if (check != .ok) @panic("fuzz: memory leaks detected");
    }

    const rounds = @import("fuzz_options").wide_iters;
    var prng = Rng.init(0x128_b17_5);
    const rnd = prng.random();

    try runGadgets(WideF, WideE, alloc, rnd, rounds);
}
