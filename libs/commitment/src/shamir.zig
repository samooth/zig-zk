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
/// The caller supplies the randomness. It used to be `Scalar.random()` with no
/// argument, which no field in this repository has: `M31` had no `random` at
/// all, so the function did not compile against anything real, and the only
/// scalar it ever compiled against returned a constant from `random`. That is
/// not a harmless test stub. With every coefficient equal to 4, a share at x
/// is `secret + 4x + 4x^2`, so one share gives the secret away to anyone who
/// knows the coefficients, and a polynomial whose coefficients are all equal is
/// a case Lagrange interpolation barely has to work for.
///
/// The randomness is a parameter rather than a call to `std.crypto.random`
/// because a caller building a transcript wants the coefficients bound to
/// something it can replay, and a caller who does not care should not have to
/// learn that to call this.
pub fn split(
    comptime Scalar: type,
    secret: Scalar,
    threshold: u32,
    num_shares: u32,
    allocator: std.mem.Allocator,
    rnd: std.Random,
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
        coeffs[i] = Scalar.random(rnd);
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
    /// A fixed generator for the error paths, which never reach the sampling.
    pub fn testRandom() std.Random {
        var prng = std.Random.DefaultPrng.init(0xabcd_ef01);
        return prng.random();
    }

    /// Real randomness, sampled by rejection. This used to return the constant
    /// 4, which is what let `split` compile for months against a polynomial
    /// that gave the secret away from a single share. A test scalar that lies
    /// about being random is worse than no test scalar: it makes the code under
    /// test look exercised when it is not.
    pub fn random(rnd: std.Random) @This() {
        // The bound is the cardinality, and it has to be: an earlier version
        // wrote `fromInt(64)`, which on a seven-element field reduces to 1, so
        // it only ever accepted 0 and every coefficient was zero. That is the
        // same defect as the constant this replaced, and the test below is what
        // caught it.
        while (true) {
            const v = rnd.int(u32);
            if (v < MODULUS) return fromInt(v);
        }
    }
};

test "Shamir split and reconstruct" {
    const secret = F7.fromInt(42 % 7); // 0
    var prng = std.Random.DefaultPrng.init(0x5eed_c0de);
    const shares = try split(F7, secret, 3, 5, std.testing.allocator, prng.random());
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
    var prng = std.Random.DefaultPrng.init(0x1357_9bdf);
    const shares = try split(F7, secret, 2, 4, std.testing.allocator, prng.random());
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
        split(F7, F7.fromInt(5), 0, 3, std.testing.allocator, F7.testRandom()),
    );
}

test "Shamir split refuses fewer shares than the threshold" {
    try testing.expectError(
        error.TooFewShares,
        split(F7, F7.fromInt(5), 3, 2, std.testing.allocator, F7.testRandom()),
    );
}

test "Shamir reconstruct refuses an empty slice" {
    try testing.expectError(error.NoShares, reconstruct(F7, &.{}));
}

test "Shamir coefficients are not the same polynomial every call" {
    // This is the assertion that was missing and the reason the constant in
    // `random` went unnoticed for as long as it did. Two splits of the same
    // secret have to differ, because equal coefficients make every share an
    // affine image of the secret and one share then reconstructs it: with
    // coeffs c1 = c2 the share at x is `secret + c1(x + x^2)`, so `secret` is
    // `y - c1(x + x^2)` to anyone who knows `c1`.
    var prng = std.Random.DefaultPrng.init(0xfeed_face);
    const rnd = prng.random();

    const secret = F7.fromInt(3);
    const a = try split(F7, secret, 3, 4, std.testing.allocator, rnd);
    defer std.testing.allocator.free(a);
    const b = try split(F7, secret, 3, 4, std.testing.allocator, rnd);
    defer std.testing.allocator.free(b);

    var differing = false;
    for (a, b) |x, y| {
        if (!x.value.eql(y.value)) differing = true;
    }
    try testing.expect(differing);

    // And the property the constant destroyed: the threshold has to be the
    // number of shares it takes. Three reconstruct; two do not, and the way to
    // say "do not" is that they give a different secret rather than an error.
    const three = [_]Share(F7){ a[0], a[1], a[3] };
    try testing.expect((try reconstruct(F7, &three)).eql(secret));

    const two = [_]Share(F7){ a[0], a[1] };
    const from_two = try reconstruct(F7, &two);
    try testing.expect(!from_two.eql(secret));
}
