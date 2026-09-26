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
| `zig-air` | `libs/air/src/root.zig` | algebra-traits | — |
| `zig-signature` | `libs/signature/src/root.zig` | algebra-traits, curve, hash, rng | — |
| `zig-snark` | `libs/snark/src/root.zig` | field, curve, pairing | — |
| `zig-stark` | `libs/stark/root.zig` | field | transcript |

## 1. transcript (Layer 1)

Fiat-Shamir transcripts over Blake3. Three types with different ergonomics:

**`Transcript`** — counter-based absorb/squeeze.

- `init(label)`, `absorb(bytes)`, `absorbField(F, x)`, `absorbFieldSlice(F, xs)`
- `squeeze(out)`, `squeezeField(F)` (rejection sampling, uniform over `F`),
  `squeezeU64()`, `squeezeU256()`
- `clone()` forks the state; `reset(label)` restarts the domain separator
- Every absorb is length-prefixed; every squeeze bumps an internal counter, so
  repeated squeezes never repeat bytes.

**`LabelledTranscript`** — every operation takes an explicit string label, so
cross-protocol confusion needs a hash collision rather than a shared prefix.

**`Channel`** — duck-typed, the shape `libs/stark` expects.

- `absorb(value)` / `absorbMany(...)` work on anything with `SIZE`, `toBytes`
  and `fromBytes` (no field trait needed)
- `absorbDigest(digest)` is the bridge for the STARK tree's internal `Digest`
  type
- `sample(T)`, `sampleIndex(n)`, `sampleBytes(out)`

## 2. commitment (Layer 2)

**`Ipa(F)`** — inner-product argument over any zig-algebra field.

- `init(allocator, n, seed)`, `deinit()`
- `commit(a, b, c) -> F`, `innerProduct(a, b) -> F`
- `prove(allocator, a, b) -> Proof`, `verify(C, *Proof) -> bool`
- Challenges come from a **running Blake3 Fiat-Shamir sponge**: every absorbed
  value feeds forward, so round *k*'s challenge binds the whole statement and
  all prior rounds. (Fixed in `986c421`; before that, challenges were derived
  from a static state and the argument was not bound.)

**Pedersen** — `Pedersen(Point)`: `commit`, `verify`, `add`, `sub`, generic
over any point type with the right operations.

**Shamir** — `Share(Scalar)`, `split`, `reconstruct`, `lagrangeCoefficient`,
plus a mod-7 test field used by the suite.

**Sigma protocols** — `SchnorrPoK(Point, Scalar)` proof of knowledge, and
`CdsOrProof(Point, Scalar)`, the CDS '94 one-out-of-many OR proof.

**`MerkleTree`** — re-export of `zig-merkle`.

Not implemented here: KZG, FRI, DARK, Ligero. FRI lives in `zig-algebra` for
the STARK stack, and KZG likewise; neither is re-exported as a commitment-scheme
API.

## 3. signature (Layer 3)

**`SchnorrSignature(Point, Scalar)`** — generic over any Point/Scalar pair with
`add`, `scalarMul`, `eql` (and `Scalar` with `fromBytes`, `zero`, `add`, `mul`).
`init(R, z)`, `verify(base, public_key, msg)`, `challenge(...)`.

**`Ed25519Impl`** — thin alias over `std.crypto.sign.Ed25519` (deterministic,
constant time, no code of ours in the hot path), together with its
`KeyPair`/`PublicKey`/`SecretKey`/`Signature` types for streaming APIs.

**secp256k1 adapters** — `libs/signature/src/root.zig` adapts
`std.crypto.ecc.Secp256k1` points/scalars to the generic Schnorr interface
(`toBytes`/`fromBytes`/`scalarMul`/`eql`).

Not implemented: ECDSA, BLS, MuSig2.

## 4. air (Layer 3)

Generic Algebraic Intermediate Representation, parameterized by field and
public-input type: `Air(BaseField, PublicInputs)`, plus `BoundaryConstraint`,
`TransitionConstraint`, `EvaluationFrame` (current/next row pair) and
`ExecutionTrace` (allocator-backed rows/columns with `get`/`set`/`getRow`/
`getCol`).

## 5. stark (Layer 4)

The canonical zig-stark tree, adopted wholesale. See `ARCHITECTURE.md` for the
two permanent adaptations (Channel lives in `zig-transcript`; M31/CM31/QM31 come
from zig-algebra via `m31/builtin.zig`).

**M31 stack** — `m31/`: circle FFT (`circle/`), NTT (`ntt/classic.zig`,
`ntt/simd.zig`, `ntt/circle.zig`), univariate polynomials (`poly/`), DEEP-FRI
(`fri.zig`), and `stark.zig` with `GenericStark(Air)` plus worked AIRs
(`FibAir`, `RangeCheckAir`, `AndTableAir`, `MultiplicityAir`).

**Binius stack** — `binius/`: tower fields, sum-check, PCS variants
(`pcs`, `packed_pcs`, `batchpcs`, `fripcs`, `addfri`), argument layer (`arg`),
`recursion/` (Poseidon2 over GF(2)), and the constraint gadgets used by the fuzz
suite (`adder`, `rangecheck`, `compare`, `bitpack`, `pack`).

**core** — `core/hash` (Blake3 + `Digest`), `core/merkle`, `bit_utils`, SIMD
helpers, serialization.

## 6. snark (Layer 4)

Groth16 over BN254: one verification primitive plus a reference prover used as
a test oracle. Not a production prover (see *Security posture*).

### Verification

```zig
pub fn verify(
    a1: G1,          // [alpha]_1
    b2: G2,          // [beta]_2
    g2: G2,          // [gamma]_2
    d2: G2,          // [delta]_2
    ic: []const G1,  // public-input encodings
    pa: G1, pb: G2, pc: G1,   // the proof
    pub_in: []const Fr,
) bool
```

Checks `e(A, B) == e(alpha, beta) * e(C, delta) * e(PV, gamma)`, i.e.
`e(-A, B) * e(alpha, beta) * e(C, delta) * e(PV, gamma) == 1`.

`ic[0]` encodes the **constant-one wire**; `ic[i + 1]` encodes public input
`i`, whose value comes from `pub_in`. A length mismatch means a malformed
proof and returns false.

Proof elements are validated for curve and prime-order-subgroup membership
before use. This is not paranoia about the maths: `zig-pairing`'s `pairing()`
returns the multiplicative identity for points that are off the curve or
outside the r-order subgroup, so without an explicit check a bogus element
would silently delete one term of the equation instead of failing the proof.

### Reference prover

```zig
const G16 = Groth16(&.{ 0, 2 }, 3, 5);   // known wires, constraints, wires
const vk = try G16.setup(&circuit, setup);
const proof = try G16.prove(&circuit, witness, setup, blind_r, blind_s);
try G16.verifyKey(vk, proof, .{output});
```

`Groth16(ic_wires, n_constraints, n_wires)` is comptime-parameterised, so the
constraint matrices are stack arrays and nothing allocates (except the caller's
`Proof`/`VerifyingKey` values). `ic_wires[0]` must be the constant-one wire; the
rest are the public inputs in order. Every other wire is private and appears
only inside the proof's `c` element.

Errors: `error.DegenerateSetup` (zeroed toxic waste, `gamma == delta`, or a
trapdoor inside the evaluation domain) and `error.QapUnsatisfied`.

### Conventions

The QAP conventions this prover depends on — the per-pair Lagrange
denominator, `A(tau)` as the interpolant of the per-constraint row
evaluations, `t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, the private-wire-only
sum in `c`, and the meaning of `ic[0]` — are written down once, with the
consequence of breaking each one, in [ARCHITECTURE.md](../ARCHITECTURE.md).

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

The root `build.zig` is canonical: it wires all six modules plus the stark e2e
and fuzz suites, and pulls zig-algebra from the pinned tarball so it works from
a bare checkout. The per-library `build.zig` files exist for standalone work
(`cd libs/<name> && zig build test`) and resolve zig-algebra from the same
pinned tarball, so they build from a bare checkout too.

The root `test` step compiles and runs every suite: 271 tests across transcript
(14), commitment (11), air (5), signature (6), stark (208), snark (11), plus
the stark e2e (16) and fuzz suites. `libs/stark/tests/fuzz.zig` is a `main`
that panics on leaks and asserts accept/reject on every round, so its pass is
carried by the assertions, not by its summary print.

CI runs the Debug suite on Linux, macOS and Windows via
`.github/actions/setup-zig`, which downloads the compiler from ziglang.org
(resolving `master` through `download/index.json`).

## Contributing

1. Protocol libraries go in `libs/<name>/` with a `build.zig` exposing one
   module.
2. New algebra needs a zig-algebra dep declared in both `build.zig` and the
   `build.zig.zon`; keep the two module tables in this file in sync.
3. Tests assert, they never print. A `std.debug.print` in a test is a bug: it
   reports nothing to the harness and it can print `true` next to a failing
   assertion.
4. Prefer an error return over `std.debug.assert` for anything a caller can
   reach through the API — asserts vanish in ReleaseFast.
5. Run `zig fmt` and the full suite before opening a PR.
