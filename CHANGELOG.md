# Changelog

All notable changes to zig-zk are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/) (0.x: MINOR may carry breaking changes).

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
