# zig-zk

> English. [Versión en español](README.es.md)

![CI](https://github.com/samooth/zig-zk/actions/workflows/ci.yml/badge.svg)

An ecosystem of cryptographic protocols and zero-knowledge proofs for Zig. Built on top of `zig-algebra`.

Requires Zig 0.16 and `zig-algebra` **v0.3.2** (pinned by hash in `build.zig.zon`).

## Documentation

Every document exists in English and Spanish; the bare file name is English and
the Spanish counterpart adds `.es`.

| Document | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Per-library API, module graph, dependency and versioning policy, security posture, testing |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Repo layering, dedupe decisions, the AIR contract, Groth16 prover conventions |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [SECURITY.md](SECURITY.md) | What is audited, what is not, what counts as a vulnerability |
| [AGENTS.md](AGENTS.md) | Working rules for agents |

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
         |  (IPA, Pedersen,    |
         |   Shamir, Sigma)    |
         +----------+----------+
                    |
Layer 3  +----------+----------+----------+
         |   signature  |   air   |  stark  |
         |  (Schnorr,  | (AIR    | (M31,    |
         |   Ed25519)  |  model) |  Binius) |
         +--------------+---------+---------+
                    |
Layer 4  +----------+----------+
         |    snark           |
         |  (Groth16 over     |
         |   BN254)           |
         +----------+----------+
```

## Libraries

| Library | Description | zig-algebra deps |
|---------|-------------|------------------|
| [transcript](libs/transcript/) | Fiat-Shamir transcripts (absorb-squeeze, domain separation, challenges, Channel) | algebra-traits, hash, rng |
| [commitment](libs/commitment/) | Commitment schemes (IPA, Pedersen, Shamir, Sigma) | algebra-traits, field, merkle, poly |
| [signature](libs/signature/) | Digital signatures (generic Schnorr, Ed25519, secp256k1 adapters) | algebra-traits, curve, hash, rng |
| [air](libs/air/) | AIR data model for STARK backends | algebra-traits |
| [stark](libs/stark/) | STARK prover/verifier (M31 DEEP-FRI + Binius stacks) | field |
| [snark](libs/snark/) | zkSNARKs (Groth16 verifier + reference prover over BN254) | field, curve, pairing |

Both tables are kept in sync with `build.zig`. The two dependency lists differ
only in the `stark` row: that is the single intra-repo edge, since stark consumes
`zig-transcript` plus zig-algebra's `field` directly. `zig build check-docs`
verifies the documentation set; the module graph itself is `build.zig`.

## Dependency Table

| Library | zig-algebra deps | zig-zk internal deps |
|---------|------------------|---------------------|
| transcript | algebra-traits, hash, rng | — |
| commitment | algebra-traits, field, merkle, poly | — |
| signature | algebra-traits, curve, hash, rng | — |
| air | algebra-traits | — |
| stark | field | transcript |
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

```zig
const std = @import("std");
const snark = @import("zig-snark");

// Reference prover for a compile-time-sized R1CS: 3 constraints, 5 wires,
// known wires {0 = the constant one, 2 = the public output}.
const G16 = snark.Groth16(&.{ 0, 2 }, 3, 5);

const vk = try G16.setup(&circuit, setup);
const proof = try G16.prove(&circuit, witness, setup, blind_r, blind_s); // error.QapUnsatisfied
try std.testing.expect(G16.verifyKey(vk, proof, .{output}));
```

## Running Tests

The root build is canonical: it wires every module and runs every suite, and it
resolves `zig-algebra` from the pinned tarball, so it works from a bare
checkout.

```bash
# Test all libraries (compiles AND runs every suite)
zig build test --summary all

# Same, optimized: the pairing-heavy snark suite goes from ~57s to ~1s
zig build test -Doptimize=ReleaseFast --summary all
```

Each library also carries its own `build.zig` for standalone work, resolving
`zig-algebra` from the same pinned tarball:

```bash
cd libs/transcript && zig build test --summary all
```

Tests assert, they never print: a `std.debug.print` in a test reports nothing to
the harness and can print `true` next to a failing assertion.

## Design Principles

1. **Correctness first** — all cryptography is mathematically verified
2. **No external dependencies** — only Zig standard library + zig-algebra
3. **Comptime-first** — all constants computed at compile time
4. **Allocation-free** — stack-only where possible
5. **Generic** — algorithms work over any field/curve via comptime parameters

## License

MIT OR Apache-2.0