// SPDX-License-Identifier: MIT OR Apache-2.0

//! Schnorr signature type.
//!
//! A Schnorr signature is a pair (R, z) where R is a nonce commitment
//! (group element) and z is the response scalar.
//!
//! Generic over any point type that supports `add`, `scalarMul`, `eql`.

const std = @import("std");

/// Schnorr signature (R, z) over a curve point type.
pub fn SchnorrSignature(comptime Point: type, comptime Scalar: type) type {
    return struct {
        const Self = @This();

        /// The nonce commitment (group element)
        R: Point,
        /// The response scalar
        z: Scalar,

        /// Create a new signature.
        pub fn init(R: Point, z: Scalar) Self {
            return .{ .R = R, .z = z };
        }

        /// Verify signature: s*G == R + e*P where e = hash(R, P, msg).
        pub fn verify(self: Self, base: Point, public_key: Point, msg: []const u8) bool {
            const e = challenge(base, public_key, self.R, msg);
            const sG = base.scalarMul(self.z);
            const eP = public_key.scalarMul(e);
            return sG.eql(self.R.add(eP));
        }

        /// Compute Schnorr challenge: H(base, public_key, R, msg).
        pub fn challenge(base: Point, public_key: Point, R: Point, msg: []const u8) Scalar {
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            // Hash base point
            hashPoint(&hasher, base);
            // Hash public key
            hashPoint(&hasher, public_key);
            // Hash nonce commitment
            hashPoint(&hasher, R);
            // Hash message
            hasher.update(msg);
            var digest: [32]u8 = undefined;
            hasher.final(&digest);

            // Reduce, do not parse. The old line was
            // `Scalar.fromBytes(digest) catch Scalar.zero()`, and it turned a
            // rejection into a challenge of zero.
            //
            // For a 254-bit field a 256-bit digest is above the modulus 81% of
            // the time, so four signatures in five had e = 0. Verification is
            // `s*G == R + e*P`, and with e = 0 that is `s*G == R`, which anyone
            // satisfies by choosing r, setting `R = r*G` and `s = r` -- no
            // private key, and the signature verifies. Worse, it is not a bad
            // signature but an empty one: two different messages produce the
            // same signature byte for byte, because the message never reached
            // the arithmetic.
            //
            // `fromInt` reduces, and there is no error to swallow, so the
            // failure cannot be reintroduced by this line. It is a compile-time
            // change rather than a branch, which is the point.
            var wide: u256 = 0;
            for (digest, 0..) |b, i| wide |= @as(u256, b) << @intCast(8 * i);
            return Scalar.fromInt(wide);
        }

        /// Hash a point into the challenge.
        ///
        /// This used to read `@hasDecl(Point, "toBytes")` and then
        /// `@hasDecl(Point, "x")`. `@hasDecl` reports declarations, not struct
        /// fields, and `x` and `y` on an affine point are fields. So the second
        /// branch could never be taken by any type at all, and a point with no
        /// `toBytes` declaration had both branches false and hashed **nothing**:
        /// no base point, no public key, no nonce commitment. The challenge then
        /// stopped binding the key, which is the property the scheme exists for.
        ///
        /// `@hasField` is the test that matches how the values are actually
        /// reached. And a point that can be hashed by neither route is rejected
        /// at compile time rather than silently contributing nothing: a group
        /// that verifies signatures without the key in the hash is a working
        /// group that does not mean what its name says.
        fn hashPoint(hasher: anytype, p: Point) void {
            if (@hasDecl(Point, "toBytes")) {
                const bytes = p.toBytes();
                hasher.update(&bytes);
            } else if (@hasField(Point, "x") and @hasField(Point, "y")) {
                const x_bytes: [32]u8 = p.x.toBytes();
                const y_bytes: [32]u8 = p.y.toBytes();
                hasher.update(&x_bytes);
                hasher.update(&y_bytes);
            } else {
                @compileError("SchnorrSignature: the point type exposes neither a " ++
                    "`toBytes` declaration nor `x`/`y` fields, so it cannot be " ++
                    "hashed into the challenge. Give it one or the other: a point " ++
                    "that cannot be hashed makes the challenge independent of the " ++
                    "public key, which is the property Schnorr exists to provide.");
            }
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Simple test field (mod 7) for testing.
/// The fixture is a real 254-bit field and a real curve point, not a stand-in.
///
/// The previous fixture was a scalar of modulus 7 whose `fromBytes` read a
/// single byte and could not fail. Neither defect in this file was reachable
/// through it: `fromBytes` never rejected, so a challenge of zero never
/// happened, and the arithmetic ran over seven elements, where most challenges
/// collapse into each other.
///
/// The other instantiation of this generic, in root.zig, is secp256k1, whose
/// scalar order sits just below 2^256. A random 32-byte digest is below it
/// almost always, so `fromBytes` almost never rejects and defect B is invisible
/// there too. Choosing a field of 254 bits is what makes it visible: a digest
/// exceeds the modulus 81% of the time.
///
/// A fixture has to choose the value that makes the defect visible, not the one
/// that makes the test easy.
const bn = @import("zig-curve").bn254;
const CurveScalar = bn.Fr;
const bn_Fp = bn.Fp;
const bn_G1 = bn.G1;

/// A point with `x` and `y` as **fields** and deliberately no `toBytes`.
///
/// That is the whole point: `hashPoint` asks `@hasDecl(Point, "toBytes")`,
/// which cannot see a field, and `@hasDecl(Point, "x")`, which cannot see a
/// field either. So with this type both branches are false and nothing at all
/// is hashed. A point type that declared a `toBytes` would hide that, which is
/// what both the modulus-7 fixture and the secp256k1 wrapper do.
const CurvePoint = struct {
    x: bn_Fp,
    y: bn_Fp,
    infinity: bool,

    pub fn zero() @This() {
        return .{ .x = bn_Fp.zero(), .y = bn_Fp.zero(), .infinity = true };
    }
    pub fn generator() @This() {
        const g = bn_G1_generator;
        return .{ .x = g.x, .y = g.y, .infinity = false };
    }
    pub fn eql(a: @This(), b: @This()) bool {
        if (a.infinity and b.infinity) return true;
        if (a.infinity or b.infinity) return false;
        return a.x.eql(b.x) and a.y.eql(b.y);
    }
    pub fn add(a: @This(), b: @This()) @This() {
        if (a.infinity) return b;
        if (b.infinity) return a;
        const pa: bn_G1 = .{ .x = a.x, .y = a.y, .infinity = a.infinity };
        const pb: bn_G1 = .{ .x = b.x, .y = b.y, .infinity = b.infinity };
        const sum = pa.add(pb);
        return .{ .x = sum.x, .y = sum.y, .infinity = sum.infinity };
    }
    pub fn scalarMul(p: @This(), s: CurveScalar) @This() {
        if (s.isZero() or p.infinity) return CurvePoint.zero();
        const pp: bn_G1 = .{ .x = p.x, .y = p.y, .infinity = p.infinity };
        const r = pp.scalarMul(s.toU512());
        return .{ .x = r.x, .y = r.y, .infinity = r.infinity };
    }
};

const bn_G1_generator = bn.G1_generator;

test "Schnorr signature creation and verification" {
    const Sig = SchnorrSignature(CurvePoint, CurveScalar);
    const G = CurvePoint.generator();

    // Simulate signing: private key x=3, public key P = x*G
    const x = CurveScalar.fromInt(3);
    const P = G.scalarMul(x);

    // Create signature manually (in real code, this would use random nonce)
    const k = CurveScalar.fromInt(2);
    const R = G.scalarMul(k);
    const e = Sig.challenge(G, P, R, "test message");
    const z = k.add(e.mul(x));

    const sig = Sig.init(R, z);

    // Verify
    try testing.expect(sig.verify(G, P, "test message"));
    try testing.expect(!sig.verify(G, P, "wrong message"));
}

test "Schnorr: el reto no es cero, y liga clave, base y nonce" {
    const Sig = SchnorrSignature(CurvePoint, CurveScalar);
    const G = CurvePoint.generator();
    const x = CurveScalar.fromInt(3);
    const P = G.scalarMul(x);
    const k = CurveScalar.fromInt(2);
    const R = G.scalarMul(k);

    // REPRO 1. With `Scalar.fromBytes(digest) catch Scalar.zero()`, a 256-bit
    // digest over a 254-bit field is out of range 81% of the time and the
    // challenge came back zero. This is deterministic, so it does not need a
    // loop and does not need probability: the first message is enough.
    const e = Sig.challenge(G, P, R, "test message");
    try testing.expect(!e.isZero());

    // The challenge has to bind the public key. This is the property defect A
    // destroyed: with nothing hashed at all, the key was not in the digest.
    const e_otra_clave = Sig.challenge(G, G.scalarMul(CurveScalar.fromInt(5)), R, "test message");
    try testing.expect(!e.eql(e_otra_clave));

    // And the nonce commitment R, which the coordinator's report notes is
    // checked by nothing: an implementation that bound the key but not R would
    // still allow a nonce to be reused.
    const R2 = G.scalarMul(CurveScalar.fromInt(9));
    const e_otro_r = Sig.challenge(G, P, R2, "test message");
    try testing.expect(!e.eql(e_otro_r));

    // And the base point, for the same reason.
    const G2 = CurvePoint.generator().add(CurvePoint.generator());
    const e_otra_base = Sig.challenge(G2, P, R, "test message");
    try testing.expect(!e.eql(e_otra_base));

    // And the message, which is what four signatures in five stopped doing.
    const e_otro_mensaje = Sig.challenge(G, P, R, "otro mensaje");
    try testing.expect(!e.eql(e_otro_mensaje));
}

test "Schnorr: una firma verifica y no verifica con la clave ajena" {
    const Sig = SchnorrSignature(CurvePoint, CurveScalar);
    const G = CurvePoint.generator();
    const x = CurveScalar.fromInt(3);
    const P = G.scalarMul(x);
    const k = CurveScalar.fromInt(2);
    const R = G.scalarMul(k);
    const e = Sig.challenge(G, P, R, "test message");
    const sig = Sig.init(R, k.add(e.mul(x)));

    try testing.expect(sig.verify(G, P, "test message"));
    try testing.expect(!sig.verify(G, P, "otro mensaje"));
    try testing.expect(!sig.verify(G, G.scalarMul(CurveScalar.fromInt(4)), "test message"));
}

test "CON e = 0 la verificacion no ata nada: s*G == R la cumple cualquiera" {
    // La aritmetica del forgery, sobre la curva real y sin clave privada en
    // ninguna parte de este test. El atacante elige r, pone R = r*G y s = r.
    const curve = @import("zig-curve").bn254;
    const Fr = curve.Fr;
    const gen = curve.G1_generator;

    const r = Fr.fromInt(123456789);
    const R = gen.scalarMul(r.toU512());
    const s = r;

    // Lo que verifica Schnorr es s*G == R + e*public_key. Con e = 0 el segundo
    // termino desaparece y la comprobacion se reduce a esto, que es lo unico
    // que el atacante ha KNOWLEDGE de porque lo ha elegido el.
    try testing.expect(gen.scalarMul(s.toU512()).eql(R));

    // Y con la clave publica real, por si alguien lee esto creyendo que hace
    // falta conocerla: e = 0 la multiplica por cero.
    const sk = Fr.fromInt(4242);
    const pk = gen.scalarMul(sk.toU512());
    const e = Fr.zero();
    try testing.expect(gen.scalarMul(s.toU512()).eql(R.add(pk.scalarMul(e.toU512()))));
}
