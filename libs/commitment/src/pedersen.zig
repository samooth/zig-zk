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

/// Simple test field (mod 7) for testing.
const F7 = struct {
    value: u64,
    pub const MODULUS: u64 = 7;

    pub fn zero() @This() { return .{ .value = 0 }; }
    pub fn one() @This() { return .{ .value = 1 }; }
    pub fn fromInt(x: u64) @This() { return .{ .value = x % MODULUS }; }
    pub fn add(a: @This(), b: @This()) @This() { return fromInt(a.value + b.value); }
    pub fn sub(a: @This(), b: @This()) @This() { return fromInt(a.value + MODULUS - b.value); }
    pub fn mul(a: @This(), b: @This()) @This() { return fromInt(a.value * b.value); }
    pub fn neg(a: @This()) @This() { return if (a.value == 0) a else fromInt(MODULUS - a.value); }
    pub fn eql(a: @This(), b: @This()) bool { return a.value == b.value; }
    pub fn scalarMul(p: anytype, s: anytype) @TypeOf(p) {
        _ = s;
        return p;
    }
};

/// Simple test point for testing (just wraps F7 values).
const TestPoint = struct {
    x: F7,
    y: F7,
    infinity: bool,

    pub fn zero() @This() { return .{ .x = F7.zero(), .y = F7.zero(), .infinity = true }; }
    pub fn eql(a: @This(), b: @This()) bool {
        if (a.infinity and b.infinity) return true;
        if (a.infinity or b.infinity) return false;
        return a.x.eql(b.x) and a.y.eql(b.y);
    }
    pub fn add(a: @This(), b: @This()) @This() {
        if (a.infinity) return b;
        if (b.infinity) return a;
        // Simplified: just add coordinates (not real curve math, just for testing)
        return .{ .x = a.x.add(b.x), .y = a.y.add(b.y), .infinity = false };
    }
    pub fn neg(a: @This()) @This() {
        if (a.infinity) return a;
        return .{ .x = a.x, .y = a.y.neg(), .infinity = false };
    }
    pub fn scalarMul(p: @This(), s: anytype) @This() {
        if (p.infinity) return p;
        const scalar_val = if (@typeInfo(@TypeOf(s)) == .@"struct") s.value else s;
        // Simplified: multiply coordinates by scalar
        return .{
            .x = F7.fromInt(p.x.value * @as(u64, @intCast(scalar_val % 7))),
            .y = F7.fromInt(p.y.value * @as(u64, @intCast(scalar_val % 7))),
            .infinity = false,
        };
    }
};

test "Pedersen commit and verify" {
    const Ped = Pedersen(TestPoint);
    const G = TestPoint{ .x = F7.fromInt(1), .y = F7.fromInt(2), .infinity = false };
    const H = TestPoint{ .x = F7.fromInt(3), .y = F7.fromInt(4), .infinity = false };

    const c = Ped.commit(@as(u64, 5), @as(u64, 3), G, H);
    try testing.expect(Ped.verify(c, @as(u64, 5), @as(u64, 3), G, H));
    try testing.expect(!Ped.verify(c, @as(u64, 5), @as(u64, 4), G, H));
}

test "Pedersen homomorphic addition" {
    const Ped = Pedersen(TestPoint);
    const G = TestPoint{ .x = F7.fromInt(1), .y = F7.fromInt(2), .infinity = false };
    const H = TestPoint{ .x = F7.fromInt(3), .y = F7.fromInt(4), .infinity = false };

    const c1 = Ped.commit(@as(u64, 2), @as(u64, 1), G, H);
    const c2 = Ped.commit(@as(u64, 3), @as(u64, 4), G, H);
    const sum = Ped.add(c1, c2);

    // sum should be commit(5, 5) = commit(5, 5 mod 7)
    try testing.expect(Ped.verify(sum, @as(u64, 5), @as(u64, 5), G, H));
}

test "Pedersen homomorphic subtraction" {
    const Ped = Pedersen(TestPoint);
    const G = TestPoint{ .x = F7.fromInt(1), .y = F7.fromInt(2), .infinity = false };
    const H = TestPoint{ .x = F7.fromInt(3), .y = F7.fromInt(4), .infinity = false };

    const c1 = Ped.commit(@as(u64, 5), @as(u64, 3), G, H);
    const c2 = Ped.commit(@as(u64, 2), @as(u64, 1), G, H);
    const diff = Ped.sub(c1, c2);

    // diff should be commit(3, 2)
    try testing.expect(Ped.verify(diff, @as(u64, 3), @as(u64, 2), G, H));
}
