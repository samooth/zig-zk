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

## Status

This is a working library, not a finished one. The table is a summary and
[TODO.md](TODO.md) is the source: `check-docs` fails when the two disagree, and a
row that says `done` in `TODO.md` and is missing here is also a failure, so work
landing in the source cannot leave this section behind.

| State | Why it exists |
|---|---|
| `done` | Implemented, and a gate turns red if it stops holding. The row names that gate and the commit |
| `in progress` | Part of it holds. The row names **which part**, because a row that cannot say that is `not started` with extra words |
| `measured` | There is a number and an instrument reproduces it on request. Deliberately not a conclusion |
| `not started` | Nothing to check. The free state: no gate can prove an absence, so these need no seal and go stale only in the conservative direction |
| `decision pending` | Blocked rather than unfinished. Somebody has to choose before it can be built |

Both columns are load-bearing and they are not the same thing. A gate is a pointer
to a mechanism and `check-contract` rejects a `done` with no gate cell. A commit is
a record of when the row became true, and `check-docs` compares it against the
cell at that commit, so a row cannot quietly move. The rows with a local gate --
nothing recomputes them on its own -- are exactly the rows where the seal is what
distinguishes them.

| Part | State | Commit | Gate |
|---|---|---|---|
| Complete the audit of `libs/signature` (reading done, external reference missing) | in progress | - | - |
| The root duplicates each library's wiring (drift fixed, duplication remains) | in progress | - | - |
| Propagate `allow_small_field` | done | `0d81e3a` | `zig build test` |
| Pin hygiene | done | `80692a3` | `zig build check-contract` |
| Constant-time claims, gated | done | `80692a3` | `zig build check-contract` |
| The round count | measured | - | - |
| Which Binius field is first-class | decision pending | - | - |
| Hash-to-curve | not started | - | - |
| BLS12-381 | not started | - | - |
| Schnorr multisignature and threshold | not started | - | - |
| Ed25519 over a prime field | not started | - | - |
| Point adapters for other curves | not started | - | - |
| DER, PEM, and interchange formats | not started | - | - |
| `core/hash` and `core/merkle` | not started | - | - |
| Hash inside the circuit | not started | - | - |

Two rows carry a local gate, meaning nothing recomputes them on their own: the
round count is a ratio between two configurations a person chose to run. A gate
that only exists when somebody remembers to run it is a memory, and the commit
column is what tells a reader when to stop trusting it.

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

## Validation Contract

What each gate here is, and what it is not. A gate that says what it does not
cover is usable; one that only says what it covers reads as a guarantee of the
whole.

`zig build test` is the entry point, and it depends on `check-docs` and
`check-contract`, so a full run is all three. It is a **guarantee about the
assertions in the suite and the rules in the two gates**. It is not a proof of
anything: not that the suite covers what matters, not that the protocols are
correct, not that the code is free of defects. The fuzz steps run a bounded
number of iterations, so a green run is a sample and not an absence.

| Gate | Guarantees | Does not guarantee |
|---|---|---|
| `zig build test` | Every assertion in the suite holds; 302 tests over 36 steps | Coverage, correctness of the protocols, absence of defects |
| `zig build check-docs` | Every markdown file has a counterpart in the other language; each declares its language and links its pair; no prose carries stopwords of the other language; no CJK, kana or Cyrillic reaches the prose; changelog versions descend without repeats or empty bodies; paired files carry the same number of sections; a state-table row has a body; a settled row names the commit that settled it and still reads the same there; the README status table agrees with `TODO.md` in both directions | That the prose is correct, that a translation is good, or that a claim in prose is true. Counts and states are checked. Prose is not |
| `zig build check-contract` | The declared contract with `zig-algebra`: assert counts per zone against a ratcheted ledger, the imported module set against the declared one, every manifest pinning the ledger's version, every wired module imported by something, the pin naming a tag that was published and no more than one release behind, the test total recomputed from source, constant-time claims declared with the channel they leak, and the stark documentation's counts against the same source | That the algorithms are secure, or that the ledger describes the intent correctly. It checks the declaration, not the world |
| `zig build check-pins-fresh` | `scripts/algebra-tags.txt` still equals the published tags upstream | Anything at all without a network, which is why it is not a dependency of `zig build test`: a gate that reaches out gives a different answer in CI than on a laptop |
| `zig build refresh-algebra-tags` | Nothing. It writes the reference from the network and is not a gate | - |
| `zig build check-release` | The tag `v<version>` exists for the version in `build.zig.zon`, is annotated and signed, resolves to a commit on `main`, and that commit's own manifest declares the same version | That CI was green at the moment the tag was cut. It reads four things out of git and is run by CI on tag pushes, not by `zig build test`: the tag does not exist until after CI is green, so a rule about the tag cannot gate the commit before it. On a shallow checkout it fails rather than skipping, because a control that quietly stops running is worse than one that is absent |

The distinction that matters when reading a green run: `check-docs` and
`check-contract` are guarantees about **this repository's own declarations**, and
the declarations are written by people. A row can be wrong in both files at once
and pass, because the gate compares two documents against each other. What the
gates remove is the class of defect where one document was edited and the others
were not, which is the class that actually happened here.

## Conventions

Both conventions below are checked, so they are not habits to keep.

**Quick Start and Running Tests stay separate.** Building and testing are two
questions with two different answers -- how do I get it, and how do I know it
works -- and merging them makes the first reader read past verification to reach
installation, or the second scroll past installation to find what the gates
guarantee. The rule is one sentence long because the choice is a decision, and a
decision that lives only in the absence of a merge reads as an oversight.

**No per-line references.** Across the twelve README files there are zero
references of the form `file.zig:123`. A line number is a promise about a
location that any edit can break, and the fix is always to delete the number
rather than update it, so the reference rots into a lie that reads as a pointer.
Link the file.

**Pairs are structurally identical.** Each of the six README pairs carries the
same number of level-2 sections:

| Pair | Level-2 sections | Lines EN | Lines ES |
|---|---|---|---|
| Root | 13 | 272 | 284 |
| `libs/commitment` | 7 | 156 | 161 |
| `libs/signature` | 8 | 143 | 141 |
| `libs/snark` | 7 | 163 | 171 |
| `libs/stark` | 11 | 240 | 249 |
| `libs/transcript` | 9 | 155 | 158 |

A pair that differs in line count is translated prose -- English and Spanish do not
wrap the same -- and not a section that went missing in one language. That
asymmetry went missing once, when a script asserted halfway and never wrote its
file, which is why `check-docs` counts sections. It also checks the table above
against the files, because a figure in prose is a claim and a figure in a table is
a measurement.

## Design Principles

1. **Correctness first** — all cryptography is mathematically verified
2. **No external dependencies** — only Zig standard library + zig-algebra
3. **Comptime-first** — all constants computed at compile time
4. **Allocation-free** — stack-only where possible
5. **Generic** — algorithms work over any field/curve via comptime parameters

## License

MIT OR Apache-2.0