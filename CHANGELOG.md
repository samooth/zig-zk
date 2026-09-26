# Changelog

> English. [Versión en español](CHANGELOG.es.md)

All notable changes to zig-zk are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/): in `0.y.z` the MINOR carries
incompatible changes and the PATCH carries additive changes and fixes only. The
policy is spelled out in [docs/architecture.md](docs/architecture.md#versioning).

## [0.2.2] - 2026-09-26

PATCH: nothing here changes a public API. Documentation, licensing, and build
files that were never wired.

### Fixed
- **build**: the per-library `build.zig` files could not build at all. They
  resolved zig-algebra as path dependencies (`../../zig-algebra`), which
  requires that repository to be checked out next to this one, and they were
  written against the old zig-algebra layout of one package per module, which
  v0.3.x replaced. They now resolve the same pinned tarball the root build uses,
  so `cd libs/<name> && zig build test` works from a bare checkout.

### Added
- `LICENSE-MIT` and `LICENSE-APACHE`. The README declared a dual license while
  neither file existed, so no license was actually being granted.
- `SECURITY.md`: which surfaces are audited, which are not, and — the part that
  is usually missing — what does *not* count as a vulnerability. Notably, a
  Groth16 prover that holds the setup trapdoor can prove anything; that is a
  property of the setup ceremony, not a bug in the prover.
- `zig build check-docs`, a build step that `zig build test` also depends on:
  verifies that every markdown file has its counterpart in the other language,
  that each one declares its language, that the prose of one has not drifted into
  the other, and that the Spanish files avoid anglicisms with a clean Spanish
  equivalent.

### Changed
- **docs**: the documentation now exists in English and Spanish. The bare file
  name is English and the Spanish counterpart adds `.es`. `AGENTS.md` and
  `ARCHITECTURE.md` were Spanish-only and now have English counterparts.
- **docs**: `README.md` no longer advertises KZG, ECDSA, BLS or PLONK as if they
  existed. The stack diagram and the library tables now match `build.zig`.
- **docs**: the Groth16 QAP conventions are written once, in `ARCHITECTURE.md`,
  instead of twice.

## [0.2.1] - 2026-09-26

### Added
- **snark**: Groth16 over BN254. `verify` checks
  `e(A,B) == e(alpha,beta) * e(C,delta) * e(PV,gamma)`, validating the proof
  elements for curve and prime-order-subgroup membership and rejecting a
  public-input arity that does not match the encodings.
- **snark**: `Groth16(ic_wires, n_constraints, n_wires)`, a comptime-generic
  reference prover for rank-1 constraint systems: `Circuit`, `Setup`,
  `VerifyingKey`, `Proof`, `setup`, `prove`, `verifyKey` and `satisfies`, over
  stack-allocated constraint matrices.
- **snark**: `error.DegenerateSetup` (zeroed toxic waste, `gamma == delta`, or a
  trapdoor inside the evaluation domain) and `error.QapUnsatisfied` (the witness
  violates a constraint, so the QAP numerator is not divisible by the vanishing
  polynomial). Errors rather than `std.debug.assert`, which vanishes in
  ReleaseFast.
- **snark**: 11 assertion-based tests covering the roundtrip, wrong public
  inputs, tampered and off-curve proof elements, a mismatched setup, blinding
  factors, malformed arity and pairing bilinearity.
- `CHANGELOG.md`.

### Docs
- `docs/architecture.md` describes the code that exists: per-library API,
  module graph, Groth16 conventions, security posture, testing.
- `ARCHITECTURE.md` and `docs/architecture.md` record the Groth16 conventions
  (`ic_wires` semantics, the one-wire `ic[0]` encoding, the private-wire-only
  sum) and the algebraic condition the pairing check verifies.
- `README.md`: documentation index and a reference-prover example.
- Stale doc-comments corrected in `zig-signature` and `zig-transcript`.

## [0.2.0] - 2026-08-26

### Added
- **stark**: the canonical zig-stark tree adopted wholesale — the M31 DEEP-FRI
  stack (circle FFT, NTT, univariate polynomials, FRI, `GenericStark` with
  worked AIRs) and the Binius stack (tower fields, sum-check, the PCS variants,
  the argument layer, Poseidon2 recursion).
- **signature**: Ed25519 via `std.crypto.sign`, plus secp256k1 adapters for the
  generic Schnorr interface.
- **commitment**: Shamir secret sharing, Pedersen commitments, Schnorr PoK and
  the CDS '94 OR proof.
- **ci**: Linux/macOS/Windows matrix driven by a local `setup-zig` composite
  action, and the canonical e2e and fuzz suites wired into the root `test` step.
- `AGENTS.md`: working rules for agents.

### Changed
- **stark**: the Fiat-Shamir Channel comes from `zig-transcript` instead of a
  vendored copy; M31/CM31/QM31 come from zig-algebra's fields via
  `m31/builtin.zig`.
- **build**: the root `build.zig` is the single entry point that wires all
  modules and runs every suite.
- **commitment**: the IPA argument derives its challenges from a running
  Fiat-Shamir sponge, so round *k*'s challenge binds the whole statement and
  all previous rounds.

### Dependencies
- **zig-algebra**: pinned as a released tarball with a content hash, so the
  repository builds from a bare checkout with no sibling repository present.
