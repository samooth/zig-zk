# zig-zk

> English. [Versión en español](README.es.md)

![CI](https://github.com/samooth/zig-zk/actions/workflows/ci.yml/badge.svg)

An ecosystem of cryptographic protocols and zero-knowledge proofs for Zig. Built on top of `zig-algebra`.

Requires Zig 0.16 and `zig-algebra` **v0.6.0** (pinned by hash in `build.zig.zon`).
The pin is what the build actually resolves, so this line is a claim about it;
`zig build check-contract` fails when the two disagree.

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
| [TODO.md](TODO.md) | Open work, ordered by what closes the most use cases |

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
| zig-algebra      |     | zig-zk           |
| (infrastructure) | --> | (protocols)      |
|                  |     |                  |
| - algebra-traits |     | - transcript     |
| - field          |     | - commitment     |
| - curve          |     | - signature      |
| - binary-field   |     | - stark          |
| - poly           |     | - snark          |
| - ntt            |     |                  |
| - fri            |     |                  |
| - kzg            |     |                  |
| - merkle         |     |                  |
| - hash           |     |                  |
| - pairing        |     |                  |
| - linalg         |     |                  |
| - bigint         |     |                  |
| - parallel       |     |                  |
| - rng            |     |                  |
| - serialization  |     |                  |
| - transcript     |     |                  |
+------------------+     +------------------+
```

`zig-algebra` provides the math. `zig-zk` provides the protocols that use that math.

The left column is the module directory of the pinned tarball, all 17 of them. It is
the pin that makes that a fact rather than a memory, and `zig build check-contract`
fails when this file and the pin disagree about the version.

## Stack

```
Layer 0  +-----------------------------------------+
         |  zig-algebra (external dependency)      |
         |  - field, curve, binary-field, poly     |
         |  - ntt, fri, kzg, merkle, hash         |
         |  - pairing, linalg, bigint, parallel   |
         |  - rng, serialization, algebra-traits  |
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

| Library | Description | Reference |
| [transcript](libs/transcript/) | Fiat-Shamir transcripts (absorb-squeeze, domain separation, challenges, Channel) | [README](libs/transcript/README.md) |
| [commitment](libs/commitment/) | Commitment schemes (IPA, Pedersen, Shamir, Sigma) | [README](libs/commitment/README.md) |
| [signature](libs/signature/) | Digital signatures (generic Schnorr, Ed25519, secp256k1 adapters) | [README](libs/signature/README.md) |
| [stark](libs/stark/) | STARK prover/verifier (M31 DEEP-FRI + Binius stacks) | [README](libs/stark/README.md) |
| [snark](libs/snark/) | zkSNARKs (Groth16 verifier + reference prover over BN254) | [README](libs/snark/README.md) |

Per-library dependencies are not repeated here: the module graph, the layering
and the versioning policy live in
[docs/architecture.md](docs/architecture.md), and `build.zig` is the wiring
itself.

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
const stark_mod = zk.module("zig-stark");
const snark_mod = zk.module("zig-snark");
```

## Quick Start

The examples live with the code they demonstrate: the `Transcript` and `Channel`
usage in the [transcript README](libs/transcript/README.md), the IPA and Pedersen
flows in the [commitment README](libs/commitment/README.md), and the Groth16
verifier and reference prover in the module docs of `libs/snark/src/root.zig`.

## Running Tests

The root build is canonical: it wires every module and runs every suite, and it
resolves `zig-algebra` from the pinned tarball, so it works from a bare
checkout.

```bash
# Test all libraries (compiles AND runs every suite)
zig build test --summary all

# Same, optimized. The snark suite executes in ~60s in Debug and ~2s in
# ReleaseFast, but a cold ReleaseFast build costs about as much as the Debug run
# because compiling the pairing code is most of that ~55s. The speedup is in the
# run, not in the build; the ~2s figure is a warm ReleaseFast build.
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