# zig-zk

![CI](https://github.com/samooth/zig-zk/actions/workflows/ci.yml/badge.svg)

An ecosystem of cryptographic protocols and zero-knowledge proofs for Zig. Built on top of `zig-algebra`.

## Vision

`zig-zk` is an **ecosystem of protocol libraries** that consumes the algebraic infrastructure from `zig-algebra` to implement STARKs, SNARKs, digital signatures, and commitment schemes.

Each library:
- Is **independently usable** (with its dependencies declared)
- Uses **comptime** for monomorphization (zero-cost)
- Is **allocation-free** where possible
- Depends on `zig-algebra` as an external package

## Relationship with zig-algebra

```
+------------------+     +------------------+
|    zig-algebra   | --> |      zig-zk      |
|  (infrastructure)|     |  (protocols)     |
|                  |     |                  |
| - algebra-traits |     | - transcript     |
| - field          |     | - commitment     |
| - curve          |     | - signature      |
| - poly           |     | - stark          |
| - ntt            |     | - snark          |
| - merkle         |     |                  |
| - pairing        |     |                  |
| - linalg         |     |                  |
+------------------+     +------------------+
```

`zig-algebra` provides the math. `zig-zk` provides the protocols that use that math.

## Stack

```
Layer 0  +-----------------------------------------+
         |  zig-algebra (external dependency)      |
         |  - field, curve, poly, ntt, merkle      |
         |  - pairing, linalg, hash, rng           |
         +-----------------------------------------+
                    |
Layer 1  +----------+----------+
         |    transcript       |
         |  (Fiat-Shamir)      |
         +----------+----------+
                    |
Layer 2  +----------+----------+
         |    commitment       |
         |  (KZG, FRI, IPA)    |
         +----------+----------+
                    |
Layer 3  +----------+----------+----------+
         |   signature  |  stark  |  snark  |
         |  (ECDSA,     | (M31,   | (Groth16|
         |   Schnorr,   |  Binius)|  PLONK) |
         |   BLS)       |         |         |
         +--------------+---------+---------+
```

## Libraries

| Library | Description | zig-algebra deps |
|---------|-------------|------------------|
| [transcript](libs/transcript/) | Fiat-Shamir transcripts (absorb-squeeze, domain separation, challenges) | algebra-traits, hash, rng |
| [commitment](libs/commitment/) | Commitment schemes (IPA, Pedersen, Shamir, Sigma; KZG/FRI planned) | field, merkle, poly |
| [signature](libs/signature/) | Digital signatures (generic Schnorr, Ed25519; ECDSA/BLS planned) | curve, hash |
| [air](libs/air/) | Generic AIR framework for STARKs | algebra-traits |
| [stark](libs/stark/) | STARK prover/verifier (M31 DEEP-FRI + Binius stacks) | — (uses zig-transcript) |
| [snark](libs/snark/) | zkSNARKs (Groth16 verifier + reference prover over BN254; PLONK planned) | field, curve, pairing |

## Dependency Table

| Library | zig-algebra deps | zig-zk internal deps |
|---------|------------------|---------------------|
| transcript | algebra-traits, hash, rng | — |
| commitment | field, merkle, poly | — |
| signature | curve, hash, rng, algebra-traits | — |
| air | algebra-traits | — |
| stark | — | transcript |
| snark | field, curve, pairing | — |

## Installation

```zig
// build.zig.zon — path dependency (local development)
.{
    .dependencies = .{
        .zig_zk = .{
            .path = "../zig-zk",
        },
    },
}
```

```zig
// build.zig
const zk = b.dependency("zig_zk", .{
    .target = target,
    .optimize = optimize,
});

// Each library is exposed as its own module:
const transcript_mod = zk.module("zig-transcript");
const commitment_mod = zk.module("zig-commitment");
const signature_mod = zk.module("zig-signature");
const air_mod = zk.module("zig-air");
const stark_mod = zk.module("zig-stark");
const snark_mod = zk.module("zig-snark");
```

## Quick Start

```zig
const std = @import("std");
const transcript = @import("zig-transcript");

// Fiat-Shamir transcript (Blake3-backed, absorb/squeeze)
var t = transcript.Transcript.init("my-protocol-v1");
t.absorb(&public_bytes);
t.absorbField(F, commitment);
const challenge = t.squeezeField(F);
```

```zig
const std = @import("std");
const signature = @import("zig-signature");

// Schnorr signatures are generic over any Point/Scalar pair supporting:
//   Point: add, scalarMul, eql   Scalar: fromBytes, zero, add, mul
// Example with a toy field/group; see libs/signature/src/root.zig for
// secp256k1 adapters over std.crypto.ecc.
const Sig = signature.SchnorrSignature(TestPoint, F7);

// Sign: R = k*G, e = H(G, P, R, msg), z = k + e*x
const sig = Sig.init(R, z);

// Verify: z*G == R + e*P
try std.testing.expect(sig.verify(G, P, "message"));
```

```zig
const std = @import("std");
const commitment = @import("zig-commitment");
const zf = @import("zig-field");

// Inner product argument over any zig-algebra field
var seed: [32]u8 = undefined;
std.mem.writeInt(u64, seed[0..8], 42, .little);
var ipa = try commitment.Ipa(zf.M31).init(allocator, 8, seed);
defer ipa.deinit();

const c = commitment.Ipa(zf.M31).innerProduct(a, b);
const C = ipa.commit(a, b, c);
const proof = try ipa.prove(allocator, a, b);
defer proof.deinit(allocator);
try ipa.verify(C, &proof);
```

```zig
const std = @import("std");
const snark = @import("zig-snark");

// Groth16 verify over BN254: e(-A,B)*e(alpha1,beta2)*e(C,delta2)*e(PV,gamma2)==1
const ok = snark.verify(a1, b2, gamma_g2, delta_g2, &ic, pi_a, pi_b, pi_c, &public_inputs);
```

## Running Tests

```bash
# Test all libraries (compiles AND runs every suite)
zig build test --summary all

# Test a specific library
cd libs/transcript && zig build test --summary all
```

## Design Principles

1. **Correctness first** — all cryptography is mathematically verified
2. **No external dependencies** — only Zig standard library + zig-algebra
3. **Comptime-first** — all constants computed at compile time
4. **Allocation-free** — stack-only where possible
5. **Generic** — algorithms work over any field/curve via comptime parameters

## License

MIT OR Apache-2.0