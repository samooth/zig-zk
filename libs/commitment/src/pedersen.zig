// SPDX-License-Identifier: MIT OR Apache-2.0

//! Pedersen commitment scheme over elliptic curves.
//!
//! C(v, r) = v*G + r*H
//!
//! Perfectly hiding, computationally binding, additively homomorphic.
//! Generic over any point type that supports `add`, `scalarMul`, `neg`, `eql`.

const std = @import("std");

/// Pedersen commitment over a curve point type.
///
/// `Point` must support:
///   - `add(a, b) Point`
///   - `scalarMul(p, s) Point` (s can be any integer type)
///   - `neg(p) Point`
///   - `eql(a, b) bool`
///   - `zero() Point` (point at infinity)
pub fn Pedersen(comptime Point: type) type {
    return struct {
        const Self = @This();

        /// C(v, r) = v*G + r*H
        pub fn commit(value: anytype, blinding: anytype, G: Point, H: Point) Point {
            const vG = G.scalarMul(value);
            const rH = H.scalarMul(blinding);
            return vG.add(rH);
        }

        /// Verify that commitment opens to (value, blinding).
        pub fn verify(commitment: Point, value: anytype, blinding: anytype, G: Point, H: Point) bool {
            return commitment.eql(commit(value, blinding, G, H));
        }

        /// Homomorphic addition: C(v1,r1) + C(v2,r2) = C(v1+v2, r1+r2)
        pub fn add(c1: Point, c2: Point) Point {
            return c1.add(c2);
        }

        /// Homomorphic subtraction: C(v1,r1) - C(v2,r2) = C(v1-v2, r1-r2)
        pub fn sub(c1: Point, c2: Point) Point {
            return c1.add(c2.neg());
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Additive group Z_7 as a toy "curve" for testing. Scalar multiplication
/// distributes over addition, so homomorphic properties hold exactly.
const Z7 = struct {
    v: u64,

    pub fn zero() @This() {
        return .{ .v = 0 };
    }

    pub fn fromInt(x: u64) @This() {
        return .{ .v = x % 7 };
    }

    pub fn eql(a: @This(), b: @This()) bool {
        return a.v == b.v;
    }

    pub fn add(a: @This(), b: @This()) @This() {
        return .{ .v = (a.v + b.v) % 7 };
    }

    pub fn neg(a: @This()) @This() {
        return .{ .v = (7 - a.v) % 7 };
    }

    pub fn scalarMul(a: @This(), s: anytype) @This() {
        const T = @TypeOf(s);
        const k: u64 = if (T == Z7) s.v else @intCast(s);
        return .{ .v = (a.v * (k % 7)) % 7 };
    }
};

test "Pedersen commit and verify" {
    const Ped = Pedersen(Z7);
    const G = Z7.fromInt(3);
    const H = Z7.fromInt(5);

    const c = Ped.commit(@as(u64, 5), @as(u64, 3), G, H);
    try testing.expect(Ped.verify(c, @as(u64, 5), @as(u64, 3), G, H));
    try testing.expect(!Ped.verify(c, @as(u64, 5), @as(u64, 4), G, H));
}

test "Pedersen homomorphic addition" {
    const Ped = Pedersen(Z7);
    const G = Z7.fromInt(3);
    const H = Z7.fromInt(5);

    const c1 = Ped.commit(@as(u64, 2), @as(u64, 1), G, H);
    const c2 = Ped.commit(@as(u64, 3), @as(u64, 4), G, H);
    const sum = Ped.add(c1, c2);

    try testing.expect(Ped.verify(sum, @as(u64, 5), @as(u64, 5), G, H));
}

test "Pedersen homomorphic subtraction" {
    const Ped = Pedersen(Z7);
    const G = Z7.fromInt(3);
    const H = Z7.fromInt(5);

    const c1 = Ped.commit(@as(u64, 5), @as(u64, 3), G, H);
    const c2 = Ped.commit(@as(u64, 2), @as(u64, 1), G, H);
    const diff = Ped.sub(c1, c2);

    try testing.expect(Ped.verify(diff, @as(u64, 3), @as(u64, 2), G, H));
}
