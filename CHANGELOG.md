# Changelog

> English. [Versión en español](CHANGELOG.es.md)

All notable changes to zig-zk are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/): in `0.y.z` the MINOR carries
incompatible changes and the PATCH carries additive changes and fixes only. The
policy is spelled out in [docs/architecture.md](docs/architecture.md#versioning).

## [0.3.0] - 2026-09-26

MINOR: the AIR contract moved into the library that consumes it, the
standalone `zig-air` module is gone, and the rule about asserts stopped being
prose.

289 tests in 22 steps, Debug and ReleaseFast. Two of them never ran before this
release: the Binius fuzz suite, which was a `main` in a test binary, and the
channel's own five tests, which nothing forced the file to be analysed for. Both
are named under Fixed.

### Changed (BREAKING)
- **stark**: the AIR contract now lives in `libs/stark/m31/air/contract.zig`,
  where `BoundaryAssertion` was already needed, and `assertAir(Air, F)` checks
  it at compile time from `GenericStark`. Nine mandatory declarations and their
  signatures, two more required when `num_preprocessed > 0`, and five when
  `num_lookup_relations > 0`. A malformed AIR now fails where it is written
  instead of producing an error from inside the prover that never mentioned
  what was missing.
- **stark**: `libs/stark/m31/air/{air,constraint,frame,trace}.zig` are removed.
  Nothing imported them; they were re-exported and never consumed.
  `zig_stark.m31.air_air`, `air_trace`, `air_frame` and `air_constraint` are
  replaced by `zig_stark.m31.air_contract`.
- **air**: the `zig-air` module is removed. Its five constructors
  (`Air`, `BoundaryConstraint`, `TransitionConstraint`, `EvaluationFrame`,
  `ExecutionTrace`) were instantiated by nothing: the prover is duck-typed and
  never built them, so the published framework was not the one the prover used.
  Delete the import and use `zig-stark`, whose `m31/air/contract.zig` now
  documents and checks what a second STARK backend would have to satisfy.

- **snark**: `Groth16(ic_wires, n_constraints, n_wires)` validates its
  arguments at compile time instead of with `std.debug.assert`, which is
  compiled out in ReleaseFast: a malformed system used to build there and fail
  on the first proof. A duplicate or out-of-range wire now fails the build with
  a message naming the argument.

- **commitment**: values a caller supplies are errors now, not asserts.
  `shamir.reconstruct` returns `error.NoShares`, `Ipa.innerProduct` and
  `Ipa.commit` return `error.LengthMismatch`, `shamir.split` returns
  `error.InvalidThreshold` or `error.TooFewShares`, and `Ipa.verify` returns
  `error.MalformedProof` for a proof whose halves differ in length.
- **stark**: `prove` and `verify` can return `error.InvalidParams` for a
  `StarkParams` whose parts do not fit together and `error.InvalidTrace` for a
  trace of the wrong shape, and `MultiplicityAir.generateTrace` returns
  `error.TraceTooShort` below four rows. All three were asserts.
- **transcript**: `Channel.sampleIndex` returns `error.EmptyRange` for `n == 0`,
  where `log2_int(usize, 0)` is undefined and the old assert vanished in
  ReleaseFast.
### Fixed
- **stark**: the Binius fuzz suite never ran. Its 2000 rounds lived in a
  `pub fn main`, and a test binary with no test declarations exits successfully
  in milliseconds, so the CI step named "incl. fuzz" was not running it. It is a
  test now, it passes, and it takes about three minutes.
- **transcript**: the five tests in `channel.zig` were never compiled in, because
  nothing forced the file to be analysed and the module root had no
  `test { std.testing.refAllDecls(@This()); }` block. The missing test counts
  and the rule that prevents a recurrence are in `docs/architecture.md`.
- **stark**: `proveWithPreprocessed` leaked 22 allocations when the FRI
  parameters were rejected, so the parameter check now runs before anything is
  allocated. The leak-checking test found it.
- **stark**: the fuzz suite printed its own summary with `std.debug.print`,
  which reports nothing to the harness.
- **commitment**: the README showed `shamir.split(allocator, secret, threshold,
  total, rng)`, a signature that never existed.

### Added
- **stark**: `M31.invChecked`, `QM31.invChecked`, `TowerField.invChecked` and
  `BinaryField.invChecked` return `error.DivideByZero`. They are used for the six
  divisors in the M31 and Binius verification paths whose value comes from the
  proof or from a Fiat-Shamir challenge, where `inv(0)` answering 0 would scale
  a term by zero instead of failing.
- **stark**: `-Dfuzz-iters` sets the number of fuzz rounds (default 2000) in the
  root and `libs/stark` builds.
- **snark**: `libs/snark` gets the `build.zig` and `build.zig.zon` the other four
  libraries already had. Without them, `zig build test` inside `libs/snark`
  silently built the repository root.
- **ci**: a step that builds and tests each library through its own `build.zig`,
  which nothing exercised before.
- **build**: `scripts/check_contract.zig` and `zig build check-contract`, wired as
  a dependency of `zig build test` so CI runs it. It holds a ledger of every
  zone under `libs/` with its total assert count, which asserts are invariants,
  and what those are keyed on; the counts are ratcheted, so one only moves when
  someone edits the ledger and says why. It also pins the `zig-algebra` version
  and the set of modules imported across the boundary. The rule it enforces is
  that an assert guarding something the caller supplies is a typed error, and
  one validating an invariant of an already-constructed value stays an assert.
  Reachability cannot be inferred from source, so the reachable total it prints
  is an upper bound: a zone that declares no invariants has had none of its
  asserts classified.

### Docs
- Every library has a README, in both languages. The API of each library lives
  there; `docs/architecture.md` keeps the module graph, the policies, security
  posture and testing, and `ARCHITECTURE.md` keeps the decisions and
  conventions. The API was previously written in three places at once, which is
  how a description of a removed feature survives in the documentation.
- Each README states what the library does not do, and `libs/snark/README.md`
  says outright that its prover is a test oracle: blinding factors come from the
  caller, it is not constant time, and it has no interop vectors yet.

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
