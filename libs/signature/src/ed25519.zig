// SPDX-License-Identifier: MIT OR Apache-2.0

//! Ed25519 signatures (RFC 8032) backed by `std.crypto.sign.Ed25519`.
//!
//! Deterministic EdDSA over Curve25519. This is a thin, explicit wrapper:
//! the std implementation handles scalar clamping, nonce derivation and
//! cofactorless verification. Streaming sign/verify are available through
//! `Ed25519.Signer`/`Ed25519.Verifier`.

const std = @import("std");

/// The underlying std implementation, re-exported for streaming APIs,
/// strict variants and advanced use.
pub const Ed25519Impl = std.crypto.sign.Ed25519;

pub const KeyPair = Ed25519Impl.KeyPair;
pub const PublicKey = Ed25519Impl.PublicKey;
pub const SecretKey = Ed25519Impl.SecretKey;
pub const Signature = Ed25519Impl.Signature;

pub const seed_length = KeyPair.seed_length;
pub const signature_length = Signature.encoded_length;
pub const public_key_length = PublicKey.encoded_length;

/// Generate a key pair from a 32-byte seed (deterministic).
pub fn keyPairFromSeed(seed: [seed_length]u8) !KeyPair {
    return KeyPair.generateDeterministic(seed);
}

/// Generate a random key pair.
pub fn keyPair(io: std.Io) KeyPair {
    return KeyPair.generate(io);
}

/// Sign a message. `noise` is optional extra randomness; null for the
/// standard deterministic nonce derivation.
pub fn sign(msg: []const u8, key_pair: KeyPair, noise: ?[Ed25519Impl.noise_length]u8) !Signature {
    return key_pair.sign(msg, noise);
}

/// Verify a signature; returns false on any verification failure.
pub fn verify(sig: Signature, msg: []const u8, public_key: PublicKey) bool {
    sig.verify(msg, public_key) catch return false;
    return true;
}

/// Strict verification (rejects non-canonical signatures more aggressively).
pub fn verifyStrict(sig: Signature, msg: []const u8, public_key: PublicKey) bool {
    sig.verifyStrict(msg, public_key) catch return false;
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ed25519 sign and verify round-trip" {
    const io = testing.io;

    const kp = keyPair(io);
    const msg = "hello zig-zk";

    const sig = try sign(msg, kp, null);

    try testing.expect(verify(sig, msg, kp.public_key));
    try testing.expect(verifyStrict(sig, msg, kp.public_key));
    try testing.expect(!verify(sig, "tampered", kp.public_key));
}

test "ed25519 deterministic from seed" {
    var seed: [seed_length]u8 = undefined;
    @memset(&seed, 7);

    const kp1 = try keyPairFromSeed(seed);
    const kp2 = try keyPairFromSeed(seed);

    try testing.expectEqualSlices(
        u8,
        &kp1.public_key.toBytes(),
        &kp2.public_key.toBytes(),
    );

    // Same seed => same signature for the same message (no external noise).
    const msg = "determinism";
    const s1 = try sign(msg, kp1, null);
    const s2 = try sign(msg, kp2, null);
    try testing.expectEqualSlices(u8, &s1.toBytes(), &s2.toBytes());
}

test "ed25519 wrong key fails" {
    const io = testing.io;
    const signer_kp = keyPair(io);
    const other_kp = keyPair(io);

    const sig = try sign("msg", signer_kp, null);
    try testing.expect(!verify(sig, "msg", other_kp.public_key));
}
