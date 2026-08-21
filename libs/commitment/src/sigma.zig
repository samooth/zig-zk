// SPDX-License-Identifier: MIT OR Apache-2.0

//! Schnorr proof of knowledge and CDS '94 one-out-of-many OR proof.
//!
//! Generic sigma protocols over any curve point type.
//! These are fundamental ZK building blocks used in FROST, confidential
//! transactions, and many other protocols.

const std = @import("std");

/// Schnorr proof of knowledge of x such that p = x * base.
///
/// Made non-interactive by Fiat-Shamir: the challenge binds [base, p, a].
pub fn SchnorrPoK(comptime Point: type, comptime Scalar: type) type {
    return struct {
        const Self = @This();

        /// The commitment (k * base).
        a: Point,
        /// The response (k + e * x).
        s: Scalar,

        /// Create a Schnorr proof of knowledge.
        pub fn prove(
            base: Point,
            p: Point,
            x: Scalar,
            k: Scalar,
            label: []const u8,
        ) Self {
            const a = base.scalarMul(k);
            const e = Self.challenge(base, p, a, label);
            return .{ .a = a, .s = k.add(e.mul(x)) };
        }

        /// Verify a Schnorr proof of knowledge.
        pub fn verify(
            base: Point,
            p: Point,
            proof: Self,
            label: []const u8,
        ) bool {
            const e = Self.challenge(base, p, proof.a, label);
            const sG = base.scalarMul(proof.s);
            const eP = p.scalarMul(e);
            return sG.eql(proof.a.add(eP));
        }

        /// Compute Fiat-Shamir challenge: H(base, p, a, label).
        pub fn challenge(base: Point, p: Point, a: Point, label: []const u8) Scalar {
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hashPoint(&hasher, base);
            hashPoint(&hasher, p);
            hashPoint(&hasher, a);
            hasher.update(label);
            var digest: [32]u8 = undefined;
            hasher.final(&digest);
            return Scalar.fromBytes(digest) catch Scalar.zero();
        }

        fn hashPoint(hasher: anytype, point: Point) void {
            if (@hasDecl(Point, "toBytes")) {
                const bytes = point.toBytes();
                hasher.update(&bytes);
            } else if (@hasDecl(Point, "toCompressedSec1")) {
                const bytes = point.toCompressedSec1();
                hasher.update(&bytes);
            } else if (@hasDecl(Point, "x") and @hasDecl(Point, "y")) {
                const x_bytes = point.x.toBytes();
                const y_bytes = point.y.toBytes();
                hasher.update(&x_bytes);
                hasher.update(&y_bytes);
            }
        }
    };
}

/// CDS '94 one-out-of-many OR proof.
///
/// Proves knowledge of x with p_trueIndex = x * base for SOME statement,
/// without revealing which. Fake branches are simulated with random (e, s).
pub fn CdsOrProof(comptime Point: type, comptime Scalar: type) type {
    return struct {
        const Self = @This();

        a_values: []Point,
        e_values: []Scalar,
        s_values: []Scalar,

        /// Create a CDS OR proof.
        pub fn prove(
            allocator: std.mem.Allocator,
            base: Point,
            statements: []const Point,
            true_index: usize,
            witness: Scalar,
            k: Scalar,
            label: []const u8,
        ) !Self {
            const n = statements.len;
            if (n == 0 or true_index >= n) return error.InvalidStatement;

            var a_values = try allocator.alloc(Point, n);
            errdefer allocator.free(a_values);
            var e_values = try allocator.alloc(Scalar, n);
            errdefer allocator.free(e_values);
            var s_values = try allocator.alloc(Scalar, n);
            errdefer allocator.free(s_values);

            // Simulate every false branch
            var fake_e_sum = Scalar.zero();
            for (0..n) |j| {
                if (j == true_index) continue;
                const e_j = Scalar.random();
                const s_j = Scalar.random();
                e_values[j] = e_j;
                s_values[j] = s_j;
                const sjG = base.scalarMul(s_j);
                const ejPj = statements[j].scalarMul(e_j);
                a_values[j] = sjG.add(ejPj.neg());
                fake_e_sum = fake_e_sum.add(e_j);
            }

            // Real branch commitment
            a_values[true_index] = base.scalarMul(k);

            // Bind the whole transcript
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hashPoint(&hasher, base);
            for (statements) |stmt| hashPoint(&hasher, stmt);
            for (a_values) |av| hashPoint(&hasher, av);
            hasher.update(label);
            var digest: [32]u8 = undefined;
            hasher.final(&digest);
            const total = Scalar.fromBytes(digest) catch Scalar.zero();

            e_values[true_index] = total.sub(fake_e_sum);
            s_values[true_index] = k.add(e_values[true_index].mul(witness));

            return .{ .a_values = a_values, .e_values = e_values, .s_values = s_values };
        }

        /// Verify a CDS OR proof.
        pub fn verify(
            base: Point,
            statements: []const Point,
            proof: Self,
            label: []const u8,
        ) bool {
            const n = statements.len;
            if (n == 0 or proof.a_values.len != n or proof.e_values.len != n or proof.s_values.len != n) return false;

            // Check sub-challenges sum to Fiat-Shamir challenge
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hashPoint(&hasher, base);
            for (statements) |stmt| hashPoint(&hasher, stmt);
            for (proof.a_values) |av| hashPoint(&hasher, av);
            hasher.update(label);
            var digest: [32]u8 = undefined;
            hasher.final(&digest);
            const total = Scalar.fromBytes(digest) catch Scalar.zero();

            var e_sum = Scalar.zero();
            for (proof.e_values) |e_j| e_sum = e_sum.add(e_j);
            if (!e_sum.eql(total)) return false;

            // Every branch equation must hold
            for (0..n) |j| {
                const sjG = base.scalarMul(proof.s_values[j]);
                const ejPj = statements[j].scalarMul(proof.e_values[j]);
                if (!sjG.eql(proof.a_values[j].add(ejPj))) return false;
            }
            return true;
        }

        /// Free proof resources.
        pub fn deinit(proof: Self, allocator: std.mem.Allocator) void {
            allocator.free(proof.a_values);
            allocator.free(proof.e_values);
            allocator.free(proof.s_values);
        }

        fn hashPoint(hasher: anytype, point: Point) void {
            if (@hasDecl(Point, "toBytes")) {
                const bytes = point.toBytes();
                hasher.update(&bytes);
            } else if (@hasDecl(Point, "toCompressedSec1")) {
                const bytes = point.toCompressedSec1();
                hasher.update(&bytes);
            } else if (@hasDecl(Point, "x") and @hasDecl(Point, "y")) {
                const x_bytes = point.x.toBytes();
                const y_bytes = point.y.toBytes();
                hasher.update(&x_bytes);
                hasher.update(&y_bytes);
            }
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "SchnorrPoK prove and verify" {
    const Secp256k1 = std.crypto.ecc.Secp256k1;
    const Scalar = Secp256k1.scalar.Scalar;
    const PoK = SchnorrPoK(Secp256k1, Scalar);

    const base = Secp256k1.basePoint;

    // Generate a keypair
    var buf: [64]u8 = undefined;
    std.Io.Threaded.global_single_threaded.io().random(&buf);
    const x = Scalar.fromBytes64(buf, .big);
    const p = base.scalarMul(x.toBytes(.big) catch unreachable);

    // Generate a nonce
    var k_buf: [64]u8 = undefined;
    std.Io.Threaded.global_single_threaded.io().random(&k_buf);
    const k = Scalar.fromBytes64(k_buf, .big);

    // Prove
    const proof = PoK.prove(base, p, x, k, "test_label");

    // Verify
    try testing.expect(PoK.verify(base, p, proof, "test_label"));
    try testing.expect(!PoK.verify(base, p, proof, "wrong_label"));
}
