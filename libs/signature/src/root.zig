// SPDX-License-Identifier: MIT OR Apache-2.0

//! zig-signature: Cryptographic signature schemes.
//!
//! Provides signature schemes over elliptic curves:
//! - Schnorr signatures (generic over Point + Scalar)
//! - ECDSA (future)
//! - Ed25519 (future)
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

/// Adapter matching the Point interface expected by SchnorrSignature
/// (add, scalarMul, eql, toBytes).
const CurvePoint = struct {
    inner: Secp256k1,

    pub fn add(a: @This(), b: @This()) @This() {
        return .{ .inner = a.inner.add(b.inner) };
    }

    pub fn scalarMul(a: @This(), s: CurveScalar) @This() {
        return .{ .inner = a.inner.mul(s.inner.toBytes(.big), .big) catch Secp256k1.identityElement };
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

    pub fn zero() @This() {
        return .{ .inner = StdScalar.zero };
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
