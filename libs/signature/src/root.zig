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

pub const SchnorrSignature = schnorr.SchnorrSignature;
pub const schnorrInit = schnorr.init;
pub const schnorrVerify = schnorr.verify;
pub const schnorrChallenge = schnorr.challenge;

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Minimal test using Secp256k1
test "SchnorrSignature basic" {
    const Secp256k1 = std.crypto.ecc.Secp256k1;
    const Scalar = Secp256k1.scalar.Scalar;

    // Generate keypair
    var buf: [64]u8 = undefined;
    std.Io.Threaded.global_single_threaded.io().random(&buf);
    const sk = Scalar.fromBytes64(buf, .big);
    const pk = Secp256k1.basePoint.scalarMul(sk.toBytes(.big)) catch unreachable;

    // Sign
    var k_buf: [64]u8 = undefined;
    std.Io.Threaded.global_single_threaded.io().random(&k_buf);
    const k = Scalar.fromBytes64(k_buf, .big);
    const sig = SchnorrSignature.init(pk, sk, k, "test");

    // Verify
    try testing.expect(schnorrVerify(pk, sig, "test"));
    try testing.expect(!schnorrVerify(pk, sig, "wrong"));
}
