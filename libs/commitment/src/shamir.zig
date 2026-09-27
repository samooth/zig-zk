// SPDX-License-Identifier: MIT OR Apache-2.0

//! Shamir Secret Sharing (SSS) over finite fields.
//!
//! Split a secret into n shares with threshold t (any t shares reconstruct).
//! Uses Lagrange interpolation for reconstruction.
//!
//! Generic over a scalar type that supports:
//!   - `zero()`, `one()`, `fromInt(u64)`, `add`, `sub`, `mul`, `inv`
//!   - `random()` for random scalar generation
//!   - `isZero()`, `eql()`

const std = @import("std");

pub fn Share(comptime Scalar: type) type {
    return struct {
        index: u32,
        value: Scalar,
    };
}

/// Split secret into n shares with threshold t (any t shares reconstruct).
/// Polynomial: f(x) = secret + a_1*x + a_2*x^2 + ... + a_{t-1}*x^{t-1}
pub fn split(
    comptime Scalar: type,
    secret: Scalar,
    threshold: u32,
    num_shares: u32,
    allocator: std.mem.Allocator,
) ![]Share(Scalar) {
    // A threshold below one, or fewer shares than the threshold, is a caller
    // mistake: both used to be asserts, which vanish in ReleaseFast and leave
    // `split` returning shares that cannot reconstruct the secret.
    if (threshold < 1) return error.InvalidThreshold;
    if (num_shares < threshold) return error.TooFewShares;

    var coeffs = try allocator.alloc(Scalar, threshold);
    defer allocator.free(coeffs);
    coeffs[0] = secret;
    for (1..threshold) |i| {
        coeffs[i] = Scalar.random();
    }

    var shares = try allocator.alloc(Share(Scalar), num_shares);
    errdefer allocator.free(shares);

    for (1..num_shares + 1) |x| {
        var y = Scalar.zero();
        var x_pow = Scalar.one();
        const x_scalar = Scalar.fromInt(@intCast(x));
        for (coeffs) |coeff| {
            y = y.add(coeff.mul(x_pow));
            x_pow = x_pow.mul(x_scalar);
        }
        shares[x - 1] = .{ .index = @intCast(x), .value = y };
    }
    return shares;
}

/// Reconstruct secret from any t shares using Lagrange interpolation at x=0.
/// `error.NoShares` for an empty slice: interpolating at x=0 over no points
/// has no answer, and returning the field's zero would look like a secret.
pub fn reconstruct(comptime Scalar: type, shares: []const Share(Scalar)) error{NoShares}!Scalar {
    if (shares.len == 0) return error.NoShares;
    var secret = Scalar.zero();

    for (shares) |share_j| {
        var lambda = Scalar.one();
        const xj = Scalar.fromInt(share_j.index);

        for (shares) |share_m| {
            if (share_m.index == share_j.index) continue;
            const xm = Scalar.fromInt(share_m.index);
            // lambda *= xm / (xm - xj)
            const diff = xm.sub(xj);
            const term = xm.mul(diff.inv());
            lambda = lambda.mul(term);
        }
        secret = secret.add(share_j.value.mul(lambda));
    }
    return secret;
}

/// Compute Lagrange coefficient for a set of x-coordinates at point x_i.
pub fn lagrangeCoefficient(
    comptime Scalar: type,
    x_coords: []const Scalar,
    x_i: Scalar,
) Scalar {
    var num = Scalar.one();
    var den = Scalar.one();

    for (x_coords) |x_j| {
        if (x_j.eql(x_i)) continue;
        num = num.mul(x_j);
        den = den.mul(x_j.sub(x_i));
    }
    return num.mul(den.inv());
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Simple test field (mod 7) for testing.
const F7 = struct {
    value: u64,
    pub const MODULUS: u64 = 7;

    pub fn zero() @This() {
        return .{ .value = 0 };
    }
    pub fn one() @This() {
        return .{ .value = 1 };
    }
    pub fn fromInt(x: u64) @This() {
        return .{ .value = x % MODULUS };
    }
    pub fn add(a: @This(), b: @This()) @This() {
        return fromInt(a.value + b.value);
    }
    pub fn sub(a: @This(), b: @This()) @This() {
        return fromInt((a.value + MODULUS - b.value) % MODULUS);
    }
    pub fn mul(a: @This(), b: @This()) @This() {
        return fromInt(a.value * b.value);
    }
    pub fn inv(a: @This()) @This() {
        if (a.isZero()) return a;
        // Fermat's little theorem: a^(p-2) mod p
        return a.pow(MODULUS - 2);
    }
    pub fn pow(base: @This(), exp: u64) @This() {
        var result = one();
        var b = base;
        var e = exp;
        while (e > 0) {
            if (e & 1 == 1) result = result.mul(b);
            b = b.mul(b);
            e >>= 1;
        }
        return result;
    }
    pub fn eql(a: @This(), b: @This()) bool {
        return a.value == b.value;
    }
    pub fn isZero(self: @This()) bool {
        return self.value == 0;
    }
    pub fn random() @This() {
        return fromInt(4);
    } // deterministic for testing
};

test "Shamir split and reconstruct" {
    const secret = F7.fromInt(42 % 7); // 0
    const shares = try split(F7, secret, 3, 5, std.testing.allocator);
    defer std.testing.allocator.free(shares);

    try testing.expectEqual(@as(usize, 5), shares.len);

    // Reconstruct from first 3 shares
    const reconstructed = try reconstruct(F7, shares[0..3]);
    try testing.expect(secret.eql(reconstructed));

    // Reconstruct from different subset
    const reconstructed2 = try reconstruct(F7, shares[1..4]);
    try testing.expect(secret.eql(reconstructed2));
}

test "Shamir threshold property" {
    const secret = F7.fromInt(5);
    const shares = try split(F7, secret, 2, 4, std.testing.allocator);
    defer std.testing.allocator.free(shares);

    // Any 2 shares should reconstruct
    const r1 = try reconstruct(F7, shares[0..2]);
    try testing.expect(secret.eql(r1));

    const r2 = try reconstruct(F7, shares[2..4]);
    try testing.expect(secret.eql(r2));
}

test "Lagrange coefficient" {
    const xs = [_]F7{ F7.fromInt(1), F7.fromInt(2), F7.fromInt(3) };
    const lc = lagrangeCoefficient(F7, &xs, F7.fromInt(1));
    // L_1(0) = (0-2)*(0-3) / (1-2)*(1-3) = (-2)*(-3) / (-1)*(-2) = 6/2 = 3 (mod 7)
    try testing.expect(lc.eql(F7.fromInt(3)));
}

test "Shamir split refuses a threshold below one" {
    try testing.expectError(
        error.InvalidThreshold,
        split(F7, F7.fromInt(5), 0, 3, std.testing.allocator),
    );
}

test "Shamir split refuses fewer shares than the threshold" {
    try testing.expectError(
        error.TooFewShares,
        split(F7, F7.fromInt(5), 3, 2, std.testing.allocator),
    );
}

test "Shamir reconstruct refuses an empty slice" {
    try testing.expectError(error.NoShares, reconstruct(F7, &.{}));
}
