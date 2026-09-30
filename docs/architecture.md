# zig-zk Architecture Documentation

> English. [Versión en español](architecture.es.md)

## Overview

`zig-zk` is a monorepo of cryptographic protocol libraries built on
[`zig-algebra`](https://github.com/samooth/zig-algebra). zig-algebra owns the
mathematics; zig-zk owns the protocols that consume it.

Everything below describes the code as it exists. Anything not listed under a
library's API does not exist, and anything listed as *not implemented* is a
roadmap item, not a promise.

## Architecture

```
External: zig-algebra v0.3.2 (math primitives, no protocol logic)
    │
Layer 1: transcript          (Fiat-Shamir: absorb/squeeze, duck-typed Channel)
    │
Layer 2: commitment          (IPA inner-product argument, Pedersen, Shamir, Σ-protocols)
    │
Layer 3: signature, air      (Schnorr + Ed25519, generic AIR framework)
    │
Layer 4: stark, snark        (full proof systems: STARK M31/Binius, Groth16)
```

The only intra-repo edge is `stark -> transcript` (the STARK tree consumes
`zig-transcript`'s Channel instead of carrying its own copy).

## Module graph

Exactly as wired in `build.zig`:

| Module | Root source | zig-algebra deps | zig-zk deps |
|---|---|---|---|
| `zig-transcript` | `libs/transcript/src/root.zig` | algebra-traits, hash, rng | — |
| `zig-commitment` | `libs/commitment/src/root.zig` | algebra-traits, field, merkle, poly | — |
| `zig-signature` | `libs/signature/src/root.zig` | algebra-traits, curve, hash, rng | — |
| `zig-snark` | `libs/snark/src/root.zig` | field, curve, pairing | — |
| `zig-stark` | `libs/stark/root.zig` | field | transcript |

## Libraries

The API of each library lives in its own README, and the doc comments in the
code carry the detail.

| Library | What it is for | Reference |
|---|---|---|
| transcript | Fiat-Shamir transcripts: `Transcript`, `LabelledTranscript`, `Channel` | [README](../libs/transcript/README.md) |
| commitment | `Ipa`, Pedersen commitments, Shamir sharing, Sigma protocols | [README](../libs/commitment/README.md) |
| signature | Generic Schnorr, Ed25519 over std, secp256k1 adapters | [README](../libs/signature/README.md) |
| stark | M31 DEEP-FRI and Binius STARK stacks | [README](../libs/stark/README.md) |
| snark | Groth16 verifier and reference prover over BN254 | [README](../libs/snark/README.md) |

Cross-cutting material is split by kind: the module graph, the dependency and
versioning policy, security posture and testing are here, while the dedupe
decisions, the AIR contract and the Groth16 prover conventions live in
[ARCHITECTURE.md](../ARCHITECTURE.md).

## Dependency management

`build.zig.zon` pins zig-algebra as a released tarball:

```zig
.zig_algebra = .{
    .url = "https://github.com/samooth/zig-algebra/archive/refs/tags/v0.3.2.tar.gz",
    .hash = "zig_algebra-0.3.2-PdVS05JfEwAc7M57KrjFSdjN2X4pIR6AxllIPzW6N85Q",
},
```

Consumers get the same modules out of the dependency:

```zig
const algebra = b.dependency("zig_algebra", .{});
const field = algebra.module("zig-field");
const curve = algebra.module("zig-curve");
const pairing = algebra.module("zig-pairing");
```

### Upgrading zig-algebra

`scalarMul` on affine/projective Weierstrass points is a 4-bit windowed ladder
in Jacobian coordinates (~8x faster, O(1) inversions). Call it instead of
hand-rolling a ladder: a local implementation is redundant and a bug risk.
`zig-snark` uses `p.scalarMul(s)` throughout.

Regenerate the hash by pointing `.url` at the new tag and running `zig build`:
the mismatch error prints the correct hash.

## Security posture

- **Constant time where it counts**: Ed25519 (`std.crypto.sign`), Blake3, and
  zig-algebra's Montgomery field arithmetic.
- **Not constant time, by design and by documentation**: `curve.scalarMul`
  branches on scalar bits; the Groth16 reference prover takes blinding factors
  from the caller and uses single scalar multiplications where a real prover
  would use MSMs. Neither is used with secret data. `libs/snark` says so in its
  module doc comment.
- **Fiat-Shamir**: every transcript type domain-separates and binds absorbed
  state forward. The IPA argument's running sponge is what makes the challenge
  sequence non-malleable.
- **Setup hygiene**: Groth16's `Setup.isValid` rejects `gamma == delta`, which
  would collapse the public/private separator, and a trapdoor inside `H`,
  which would make `t(tau)` zero.

## Versioning

SemVer, with the usual `0.x` convention zig-algebra also uses: in `0.y.z`, the
MINOR carries incompatible changes and the PATCH carries additive changes and
fixes only.

| Change | Version |
|---|---|
| Fixing a bug, adding a test, documentation, or a build file that was not wired | PATCH |
| Adding a function, a type, or a whole module | PATCH (additive) |
| Changing or removing a public signature, moving a type between modules, or a change of behaviour that a consumer could depend on | MINOR |
| Anything a consumer must edit to keep building | MINOR |

There is no `1.0.0` in sight, so MINOR is the release channel for breaking
changes; the PATCH line stays boring on purpose.

The manifest version and the git tag are set in the same release commit, and
the tag points at it. A release commit contains: the `build.zig.zon` bump, the
`CHANGELOG.md` section, and nothing else. Commits and tags are GPG-signed.

## Documentation languages

Every markdown file exists in English and Spanish. The bare name is English
(so GitHub serves it by default) and the Spanish counterpart carries the
`.es.md` suffix; each file links to its pair in its first two lines.
`zig build check-docs`, which `zig build test` also depends on, verifies that
the pairs exist, that each file declares its language, that Spanish prose has
not drifted into English or vice versa, and that the Spanish files avoid
anglicisms with a clean Spanish equivalent. Code blocks and identifiers are
exempt, since those are the same in both languages.

## Testing

```bash
zig build test --summary all                    # all suites, Debug
zig build test -Doptimize=ReleaseFast           # same, ~20x faster for snark
```

The root `build.zig` is canonical: it wires all five modules plus the stark e2e
and fuzz suites, and pulls zig-algebra from the pinned tarball so it works from
a bare checkout. The per-library `build.zig` files exist for standalone work
(`cd libs/<name> && zig build test`) and resolve zig-algebra from the same
pinned tarball, so they build from a bare checkout too.

The root `test` step compiles and runs every suite: 255 tests across transcript
(20), commitment (17), signature (6), stark (162), snark (13), the two gates'
own tests (9 and 2), six that import the published modules by name, the three
known-answer suites that guard the layer consumed
from zig-algebra (3, 2 and 3), plus the stark e2e (16) and fuzz (2) suites.
`libs/stark/tests/fuzz.zig` runs 2000 rounds over three gadgets under a
leak-checking allocator and asserts accept and reject on every round; the second
of its two suites does the same over a 128-bit extension in far fewer rounds,
because a 128-bit tower product is expensive enough to be avoided in Debug
elsewhere in this file. Together they take about three minutes.

That total is checked rather than written. `zig build check-contract` fails if
either architecture document states a different one, so the number lives in
`scripts/check_contract.zig` and moves only when someone edits the ledger and
says why.

A test in a new file only runs if something forces that file to be analysed: a
`test { std.testing.refAllDecls(@This()); }` block in the module root, or a
reference to the file from a test. Without one, the test runner compiles a
binary with zero tests in it and reports a pass in milliseconds. The transcript
channel and the Binius fuzz suite were both in that state, so the counts above
are the ones to compare against, not the number of `test` declarations in the
tree.

### What a green run does not establish

A pass is a claim about what ran, not about what was true. These are the ways
this repository has found a green run that meant less than it looked, each with
what actually closes it.

| Failure | What it looks like | What closes it |
|---|---|---|
| The test never ran | A file added, its test declared, and the runner reports a pass in milliseconds because nothing forced the file to be analysed | A `test { std.testing.refAllDecls(@This()); }` in the module root, or a reference from another test |
| The code runs, but no input takes the branch | A function that is called constantly, and never through the route that matters. `mulRec` is called on every host, because `mulFast` builds its tables with it, yet on x86-64 no *product* reaches it through `mul`, which dispatches to `mulFast` | A test that drives that specific route, not one that passes through wherever. `libs/stark/tests/tower_mul.zig` |
| The check looked somewhere else | Every zone reports zero and every declared module unused, because the working directory was not the repository root and the walk found nothing | Failing when the input is implausible, not only when it disagrees: a gate that reads no manifest, or finds no repository marker, says so |
| The check passed on a smaller input | "2 files, all paired" read as documentation verified, from a walk that saw two files in a directory that holds two | Printing what it looked at, and refusing to succeed below a floor |

The fourth row is the one that needs the fewest words to stay true: a count in
the output is a claim, and a count nobody compares against is decoration.

The scope of any individual check is stated once, next to the check, and not
copied here. `tests/tower_mul.zig` is the worked example of a check that is
deliberately narrow and says so at the top of the file: it compares the two
tower multiplications, and it cannot catch a defect both share, because
agreement between two implementations is not correctness. Repeating that
sentence in a second place would be a second copy of a claim, and this
repository has spent a release deleting those.

CI runs the Debug suite on Linux, macOS and Windows via
`.github/actions/setup-zig`, which downloads the compiler from ziglang.org
(resolving `master` through `download/index.json`).

## Contributing

1. Protocol libraries go in `libs/<name>/` with a `build.zig` exposing one
   module.
2. New algebra needs a zig-algebra dep declared in both the root `build.zig` and
   the library's own `build.zig.zon`; keep the module graph above in sync. A new
   library needs a README, which is the reference for its API.
3. Tests assert, they never print. A `std.debug.print` in a test is a bug: it
   reports nothing to the harness and it can print `true` next to a failing
   assertion.
4. A caller-supplied value is an error return, never a `std.debug.assert`:
   asserts vanish in ReleaseFast, where the call then does the wrong thing
   quietly. That covers constructor arguments, slice shapes, and anything
   divided by. Internal invariants between two functions of the same
   implementation stay asserts, because there is no caller to answer to.
5. Dividing by a value that came from a proof uses the checked variant
   (`invChecked`), which returns `error.DivideByZero`. A zero divisor in a
   verification path is attacker-influenced: `inv(0)` answering 0 would scale a
   term by zero and let the round pass.
6. Run `zig fmt` and the full suite before opening a PR.
