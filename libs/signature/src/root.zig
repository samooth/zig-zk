// SPDX-License-Identifier: MIT OR Apache-2.0

//! zig-signature: Cryptographic signature schemes.
//!
//! Provides signature schemes over elliptic curves:
//! - Schnorr signatures (generic over Point + Scalar)
//! - Ed25519 (delegated to std.crypto.sign.Ed25519)
//! - ECDSA (future)
//! - BLS (future)

const std = @import("std");

pub const schnorr = @import("schnorr.zig");
pub const ed25519 = @import("ed25519.zig");

pub const SchnorrSignature = schnorr.SchnorrSignature;

test {
    std.testing.refAllDecls(@This());
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

const Secp256k1 = std.crypto.ecc.Secp256k1;
const StdScalar = Secp256k1.scalar.Scalar;

/// Adapter matching the Point interface expected by SchnorrSignature: `add`,
/// `scalarMul`, `eql`, and one of `toBytes` or `x`/`y` fields.
///
/// The hashing requirement is not a suggestion. `SchnorrSignature` rejects at
/// compile time a point that offers neither, because a point that cannot be
/// hashed leaves the public key out of the challenge, and that is the property
/// Schnorr exists to provide. This adapter has `toBytes`, so it is on the first
/// path.
const CurvePoint = struct {
    inner: Secp256k1,

    pub fn add(a: @This(), b: @This()) @This() {
        return .{ .inner = a.inner.add(b.inner) };
    }

    /// Dead as written, for two independent reasons, and both are worth writing
    /// down rather than leaving as a `catch` that reads as if it meant something.
    ///
    /// It used to be `... catch Secp256k1.identityElement`. That is the shape of
    /// the `catch Scalar.zero()` in the Schnorr challenge -- a rejection turned
    /// into a value -- and the value is the worst possible one here, because the
    /// identity is what makes Schnorr degenerate: if `e*P` were the identity then
    /// `s*G == R + e*P` would reduce to `s*G == R`, the forgery condition.
    ///
    /// Measured, because assuming this would have been the mistake:
    ///
    /// - `CurveScalar` cannot hold a non-canonical scalar. `fromBytes` rejects
    ///   one, `fromInt` reduces, and `add` and `mul` of scalars below the order
    ///   stay below it. So the value `mul` is handed is always canonical.
    /// - and `mul` does not reject a non-canonical 32-byte scalar either. Checked
    ///   against `0xff` repeated 32 times, which is above the order: accepted.
    ///
    /// So the catch would not have fired even for a scalar the wrapper forbids.
    /// It was dead code. It is an assert plus `unreachable` now, and the shape
    /// matters: the catch block never produces a value, so there is no wrong
    /// answer left in it. That is the whole difference from the `catch
    /// Scalar.zero()` in the challenge, which *did* produce a value and that
    /// value was the forgery condition.
    ///
    /// In Debug and ReleaseSafe the assert says which invariant broke. In
    /// ReleaseFast it compiles away and only `unreachable` remains, which is
    /// undefined behaviour -- so this is "this cannot happen, and if it ever
    /// does the program has no defined answer", not a graceful failure. The
    /// alternative to `unreachable` is returning something, and every something
    /// here is the degenerate value. That is why it is this and not a typed
    /// error: an error here would mean a fallible signature on the adapter for a
    /// case its own constructors forbid.
    pub fn scalarMul(a: @This(), s: CurveScalar) @This() {
        const m = a.inner.mul(s.inner.toBytes(.big), .big) catch {
            std.debug.assert(false and "CurveScalar holds a non-canonical scalar");
            unreachable;
        };
        return .{ .inner = m };
    }

    pub fn toBytes(self: @This()) [65]u8 {
        return self.inner.toUncompressedSec1();
    }

    pub fn eql(a: @This(), b: @This()) bool {
        return a.inner.equivalent(b.inner);
    }
};

/// Adapter matching the Scalar interface expected by SchnorrSignature
/// (fromBytes, zero, add, mul).
const CurveScalar = struct {
    inner: StdScalar,

    pub fn fromBytes(bytes: [32]u8) !@This() {
        return .{ .inner = try StdScalar.fromBytes(bytes, .big) };
    }

    /// The challenge is now reduced through `fromInt` rather than parsed with
    /// `fromBytes`. Parsing is the wrong contract for it: a 32-byte digest is a
    /// uniform draw, not an encoding, and for a field narrower than the digest
    /// four draws in five are out of range. `fromInt` reduces, has no error to
    /// swallow, and so cannot be turned into a challenge of zero by a catch.
    pub fn fromInt(x: u256) @This() {
        // `fromBytes64` reduces, so there is no out-of-range case and no error
        // for a caller to turn into a challenge of zero. Placing the integer in
        // the low half of a zeroed 64-byte buffer is the reduction of a 512-bit
        // value whose top half is zero.
        var wide: [64]u8 = [_]u8{0} ** 64;
        std.mem.writeInt(u256, wide[0..32], x, .little);
        return .{ .inner = StdScalar.fromBytes64(wide, .little) };
    }

    pub fn zero() @This() {
        return .{ .inner = StdScalar.zero };
    }

    pub fn eql(a: @This(), b: @This()) bool {
        return a.inner.equivalent(b.inner);
    }

    pub fn add(a: @This(), b: @This()) @This() {
        return .{ .inner = a.inner.add(b.inner) };
    }

    pub fn mul(a: @This(), b: @This()) @This() {
        return .{ .inner = a.inner.mul(b.inner) };
    }
};

test "Schnorr sign/verify over secp256k1" {
    const Sig = SchnorrSignature(CurvePoint, CurveScalar);
    const io = testing.io;

    // Key pair: P = x*G
    const x = CurveScalar{ .inner = StdScalar.random(io) };
    const G = CurvePoint{ .inner = Secp256k1.basePoint };
    const P = G.scalarMul(x);

    // Sign with nonce k: R = k*G, z = k + e*x
    const k = CurveScalar{ .inner = StdScalar.random(io) };
    const R = G.scalarMul(k);
    const e = Sig.challenge(G, P, R, "test message");
    const z = k.add(e.mul(x));

    const sig = Sig.init(R, z);

    try testing.expect(sig.verify(G, P, "test message"));
    try testing.expect(!sig.verify(G, P, "wrong message"));

    // Wrong public key must fail
    const x2 = CurveScalar{ .inner = StdScalar.random(io) };
    const P2 = G.scalarMul(x2);
    try testing.expect(!sig.verify(G, P2, "test message"));
}

test "Schnorr over secp256k1: el reto no es cero y liga clave, base y nonce" {
    const Sig = SchnorrSignature(CurvePoint, CurveScalar);
    const io = testing.io;

    const x = CurveScalar{ .inner = StdScalar.random(io) };
    const G = CurvePoint{ .inner = Secp256k1.basePoint };
    const P = G.scalarMul(x);
    const k = CurveScalar{ .inner = StdScalar.random(io) };
    const R = G.scalarMul(k);

    const e = Sig.challenge(G, P, R, "test message");
    try testing.expect(!e.eql(CurveScalar.zero()));

    // The same three axes as the BN254 fixture. This instantiation had none of
    // them, which is how the challenge could stop binding the key and the suite
    // stayed green here as well as there.
    const e_otra_clave = Sig.challenge(G, G.scalarMul(CurveScalar{ .inner = StdScalar.random(io) }), R, "test message");
    try testing.expect(!e.eql(e_otra_clave));

    const R2 = G.scalarMul(CurveScalar{ .inner = StdScalar.random(io) });
    const e_otro_r = Sig.challenge(G, P, R2, "test message");
    try testing.expect(!e.eql(e_otro_r));

    const G2 = G.add(G);
    const e_otra_base = Sig.challenge(G2, P, R, "test message");
    try testing.expect(!e.eql(e_otra_base));

    const e_otro_mensaje = Sig.challenge(G, P, R, "otro mensaje");
    try testing.expect(!e.eql(e_otro_mensaje));
}

test "esta instanciacion no puede cazar el defecto del reto cero, y por que" {
    // Written as a test so the reason is not lost with the fixture. The defect
    // was `fromBytes(digest) catch Scalar.zero()`: a 256-bit digest over a field
    // narrower than itself rejects, and the catch turned that into a challenge
    // of zero. secp256k1's order sits just below 2^256, so the rejection
    // probability is (2^256 - n) / 2^256 = 3.73e-39, about 2^-127, and the
    // defect was invisible here no matter how many times the suite ran.
    //
    // So this fixture guards the axes above and cannot guard that one. The
    // BN254 fixture in schnorr.zig, at 254 bits, is the only thing standing
    // between the repository and a repeat of it. That is the range corollary: the
    // two ends of the range, and the defect only lives in the middle.
    const order = Secp256k1.scalar.field_order;
    // 2^255 <= order < 2^256, so a uniform 256-bit draw is below it almost always.
    try std.testing.expect(order > (@as(u256, 1) << 255));
    try std.testing.expect(order <= std.math.maxInt(u256));
    try std.testing.expect(!@hasDecl(@import("schnorr.zig"), "MIN_DIGEST_BITS"));
}
