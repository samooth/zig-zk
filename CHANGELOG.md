# Changelog

> English. [Versión en español](CHANGELOG.es.md)

All notable changes to zig-zk are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/): in `0.y.z` the MINOR carries
incompatible changes and the PATCH carries additive changes and fixes only. The
policy is spelled out in [docs/architecture.md](docs/architecture.md#versioning).

## [Unreleased]

### Fixed

- **The published `0.7.0` range is an enumeration where a predicate was meant.**
  Its first line says "v0.2.0 through v0.6.0", and that range is correct: measured
  tag by tag, all seven published tags in it carry both defects. It is also the
  form that needs maintaining. A list of tags has to be updated when a tag is cut,
  and the failure mode when it is not is silent -- a reader checks whether their tag
  is in the list, and if it is not there, concludes they were not affected.

  The predicate form cannot go stale: *every published tag of this repository before
  `v0.7.0`*. `SECURITY.md` and `libs/signature/README.md` now say it that way, and
  the `0.7.0` section of this changelog says what it says.

  Recorded rather than rewritten. The `v0.7.0` tag is signed, its entry is what
  shipped, and a correction that edits it in place reads as a moved tag. The
  enumeration was not wrong -- it was the kind of thing that goes wrong later.


## [0.7.0] - 2026-09-30

**Signatures issued by v0.2.0 through v0.6.0 are not commitments. Four in five
of them carry a zero challenge, and none of them binds the public key. Every
signature issued before this version is not a commitment and has to be
regenerated.**

### Changed (BREAKING)

- **BREAKING: `Scalar` now requires `fromInt`, and `Point` has to be hashable.**
  These are the two changes that make this a MINOR, so they are declared here
  rather than left to be discovered at the call site:

  - `SchnorrSignature.challenge` used to build the challenge with
    `Scalar.fromBytes(digest) catch Scalar.zero()`. It now reduces the digest into
    a `u256` and calls `Scalar.fromInt(wide)`. A `Scalar` that provided only
    `fromBytes` therefore **no longer compiles**.
  - The branch that hashed a `Point` tested `@hasDecl(Point, "x")`, which is false
    for every field, so the `x`/`y` path was dead code and a `Point` without
    `toBytes` silently produced a challenge that did not see the commitment. A
    `Point` must now provide `toBytes`, or fields `x` and `y`, or the build stops
    with a `@compileError` naming the type. A `Point` that relied on compiling
    without either **no longer compiles**.

  The second one is the more consequential: it did not fail, it produced a valid
  looking signature over a challenge that did not include the public key or `R`,
  which is why `s*G == R` accepts `R = r*G`, `s = r` with no private key in
  scope. `Point` types in this repository are affected where they expose `x`/`y`.

### Fixed
- **The `0.6.0` record understates this, by omission.** `0.6.0` records the
  Schnorr challenge as "irrepetibilidad rota", in the shared terms of the "not
  addressed here" section, and defers it. That omits two things that change what a
  reader would do:

  - **four signatures in five are not signatures.** `P(rejection) = 0.810969`, so
    the expected count is 4.05 in 5, and two different messages produce the same
    signature byte for byte because the message never reached the arithmetic;
  - **and it was forgeable throughout**, since `s*G == R` accepts any `r` with
    `R = r*G` and `s = r`, with no private key involved.

  The tag is signed, so `0.6.0` says what it says and is not rewritten here.
  `SECURITY.md` carries the correction next to it and does not wait for a version
  name, which is the point of an advisory being separate from a changelog. This
  entry is the second place, and it is where someone updating the pin will read
  it.
### Changed

- **zig-algebra moves from `0.5.2` to `0.6.0`.** The two P0s fixed in `0.6.0`
  are the primitive-root-of-unity underflow and the PRNG that was not the one it
  said; both are recorded in that repository's `SECURITY.md`. Neither is reachable
  through this repository's surface, and the reason is worth stating rather than
  assuming: `zig-rng` is neither wired into any `build.zig` here nor imported by
  any `.zig` -- zero of both, checked, and consistent with `zig-rng` having been
  removed. The primitive root is still outstanding in `libs/stark/m31/field/m31.zig`
  and is deferred, so this pin does not close that one.

  The pin moved for the dependency, not for this repository. What it does change
  here is that the hash advisory above is now satisfied by `0.6.0` rather than by
  `0.5.2`, and the BLAKE3 defect in `libs/hash/src/blake3.zig` was not the
  transcript's hash: this repository imports the one from `zig-algebra`, so the
  challenge-breaking upgrade it describes is not a second occurrence.


### Fixed

- **`SchnorrSignature` challenges were zero four times out of five, and never
  contained the public key.** Two independent defects in one function, both found
  from outside. `SECURITY.md` has the advisory; this is the changelog's share.

  The challenge was `Scalar.fromBytes(digest) catch Scalar.zero()`. The BN254
  scalar field is 254 bits and a SHA-256 digest is 256, so the draw is out of
  range 81.1% of the time -- measured, `1 - modulus / 2^256 = 0.810969`.
  Verification is `s*G == R + e*P`; with `e = 0` that is `s*G == R`, which anyone
  satisfies by choosing `r`, setting `R = r*G` and `s = r`, with no private key
  anywhere. And it is not a weak signature but an absent one: two different
  messages produce the same signature byte for byte, because the message never
  reached the arithmetic. The suite now demonstrates the forgery on the real
  curve, using no secret.

  `hashPoint` tested `@hasDecl(Point, "toBytes")` and then `@hasDecl(Point, "x")`.
  `@hasDecl` reports declarations, not fields, and `x` and `y` on an affine point
  are fields, so the second branch could never be taken by any type and a point
  without a `toBytes` declaration hashed **nothing**. It is now `@hasField`, and a
  point that cannot be hashed by either route is a `@compileError` rather than a
  group that verifies signatures without the key in the hash.

  The challenge is reduced through `fromInt` instead of parsed with `fromBytes`,
  so there is no error left to swallow and `catch` is gone.

  Ed25519 is unaffected: it is delegated to `std.crypto.sign.Ed25519` and never
  goes through `SchnorrSignature`. "The signature library is broken" and "half of
  it is" are different claims, and this is the second.

  `0.6.0` recorded this as "irrepetibilidad rota" and scheduled it for `0.6.1`,
  which reads as routine work. It was a forgeable signature in a release, so the
  advisory exists separately from the changelog.

### Fixed (tests)

- **The `schnorr.zig` fixture is a real 254-bit field and a real curve point.**
  It was a scalar of modulus 7 whose `fromBytes` read one byte and could not fail,
  so no challenge of zero was reachable and the arithmetic ran over seven
  elements, where most challenges collapse into each other. The other
  instantiation, in `root.zig`, is secp256k1, whose scalar order sits just below
  `2^256`, so a 32-byte digest is below it almost always and the same defect is
  invisible there too. Between them, every instantiation sat where the defects
  could not show.

  That is the fifth time in this repository that a test caught nothing because the
  fixture was degenerate, after `x^n` in a domain of order `n`, `fromInt(64)` in a
  field of seven elements, an `eql` that compared an element with itself, and
  `findGenerator` without a mutation. The rule goes into `AGENTS.md`.

  Three regression tests, each confirmed by mutation: the challenge is not zero,
  and it differs when the public key, `R`, the base point or the message differ.
  The `R` assertion is the one that was missing -- an implementation that bound the
  key but not `R` would still allow a nonce to be reused.

## [0.6.0] - 2026-09-30

A minor, and the reason is in the first entry below: `shamir.split` changes
signature, and the commitment library is not something you can upgrade around.
267 tests in 32 steps, up from 252 in 30.

### Changed (BREAKING)

- **commitment: `shamir.split` takes the randomness as a parameter.** It used to
  call `Scalar.random()` with no argument, which no field in this repository or in
  the pin has, so it compiled only against test-local scalars and the coefficients
  it produced were the constant 4. A caller now passes a `std.Random`. This is
  both a signature change and a behaviour change: the polynomial is no longer the
  same one every time, which is the whole point, so a caller who depended on
  reproducible shares was depending on the defect.

  Callers who do not care should not have to learn anything to make this work,
  and callers who do care get the coefficients bound to something they can replay.

- **transcript: `squeezeField` derives the width from `F.MODULUS` rather than
  `F.order`.** A type that declares `order` and not `MODULUS` no longer compiles.
  Every field in this repository and in the pin declares `MODULUS` and none
  declares `order`, so this breaks nothing that ever compiled outside a test
  file; it makes the requirement name the declaration that actually exists.



### Added

- **A consumer, and the gate that was missing.** `consumer/` is a package that
  uses all five libraries through their public API and nothing else -- five
  modules, no relative import, so no file is reachable that a caller could not
  reach. It is an executable rather than a test, because that is what a stranger
  builds. `zig build run` in that directory is the check.

  It cannot be a dependency of the root package: it already depends on the
  libraries, so the root depending on it would be a cycle. So the gap it exposes
  about the *root's own* wiring is closed separately, by `tests/published_api.zig`,
  which imports the five modules by the names they are published under with no
  wiring of its own and runs on every `zig build test`.

  The category here is new and it is larger than the ones this repository has
  been removing. The others were code without a test, tests that did not look,
  gates that did not look, numbers measured against the wrong base. This one is
  that **the public API was never exercised from outside**, and in all seven
  cases below the difference was a `pub`, a signature, or a copy of the wiring
  that nobody compiled. A suite of 254 tests inside the modules cannot see any of
  it.


- **`Channel.reset(label)`**, which returns a channel to its state after `init`.
  A channel is stateful, so a prover and verifier sharing one sample different
  challenges and the verifier returns `false` with no error anywhere -- the worst
  shape a failure can have, because it looks like a wrong proof rather than a
  wrong channel. Two channels with one label is the correct way; this makes the
  wrong way recoverable instead of mysterious.

- **`M31.random(rnd)`, `M31.toInt`, `M31.div`, `M31.eql`, `M31.inverse` and
  `M31.isZero`.** `M31` was the only field in the tree that could not be passed
  to anything asserting the pin's `FieldTrait`, which is why
  `Transcript.squeezeField` rejected it and why `absorbField` could not reach it.
  `random` rejects rather than reduces, because a draw folded modulo 2^31 - 1 maps
  two values onto the same element.


- Groth16 interoperability, in the direction that decides whether this
  repository's verifier is usable on other people's proofs. `libs/snark` now
  carries a verification key, a proof and a public signal produced by **snarkjs
  0.7.6** on BN254, and the suite verifies that proof with `verify`. The
  negative case is asserted too: the same vector under a public input of 22
  rather than 21 must be rejected, without which a verifier that returns true
  for everything would look identical from the outside.

  The vectors are `@embedFile`d rather than read at runtime, so the test cannot
  come to depend on a working directory, and the parsers divide by the
  projective `z` rather than assuming it is one -- an assumption that happens to
  hold on the committed file is exactly what breaks on someone else's proof.
  `libs/snark/src/vectors/regenerate.mjs` is the recipe, and it is deliberately
  not a byte-for-byte reproducer: `powersoftau new` draws fresh randomness, so
  what a re-run guarantees is the shape, which is the part that keeps the test's
  parser from having been fitted to one lucky file.

  The reverse direction -- this repository's prover producing a proof snarkjs
  accepts -- has been checked once and holds, including the convention that
  `ic[0]` is the point at infinity. It is not enforced by `zig build test`,
  because that would make a Node runtime a test dependency.

### Fixed

- **`shamir.split` gave the secret away, and every configuration in which it was
  ever compiled, run and accepted was that configuration.**

  It called `Scalar.random()` with no argument. No field in this repository has
  that: `M31` had no `random` at all, and every field in the pin takes an
  `std.Random`. The function therefore compiled only against test-local scalars,
  and the one in `shamir.zig` returned the constant `4`, annotated
  *"deterministic for testing"*.

  So the polynomial was always `secreto + 4x + 4x^2 + ...`: every coefficient
  after the secret equal to 4. Any single share at any `x` then yields
  `secreto = y - 4(x + x^2 + ...)`, because the attacker knows the
  coefficients. Shamir's threshold property is not merely weakened, it is
  **inverted**: instead of requiring `k` shares, one is enough. A party holding
  one share holds the secret.

  This is not a compile failure and not a bad default. Every time this library
  was built, exercised and declared working, it was being exercised in exactly
  the mode that discloses the secret, and no test could have seen it, because
  the test double was the thing protecting the defect. The double claimed to be
  random and was not, and a double that lies about being random is worse than no
  double: it makes code that was never run look like code that was.

  Three changes, and the third is the one that matters. `split` now takes the
  randomness as a parameter, because a caller building a transcript wants the
  coefficients bound to something it can replay. The test scalar samples it for
  real, by rejection. And a test asserts that two splits of the same secret
  differ, which is the assertion whose absence let this sit for the life of the
  library.

  That last test caught the same defect in the first attempt at the fix, in this
  same commit. The rejection bound was written `fromInt(64).value`, and
  `64 mod 7 = 1`, so it accepted zero and nothing else: every coefficient was
  still the same constant, and the code read as though it were checked. A bound
  that looks like a bound and is not one is worse than no check at all, because
  it is satisfied by construction and occupies the place of one that would
  check something. The same shape has turned up four times in this repository
  now -- here, in a `eql` that compared an element with itself, in a tautological
  polynomial check, and in a Groth16 assumption of `z == 1` -- and they are one
  defect, not four.

  The defect was recorded at the five places a future refactor would have to
  touch to reintroduce it: the doc comment on `split`, the `random` that used to
  return the constant, the rejection bound, the test that is missing without it,
  and the threshold property the constant destroyed.


- **Two published soundness claims were false, and they were corrected in this
  file without the changelog saying so.** Both are restored here to what the tag
  says, so the record shows what each release shipped rather than what later
  thought it should have.

  The first was published in **0.5.0**: an eight-bit extension was given as
  "about 0.4%, and it composes over the rounds". The per-round figure is about
  2^-8, and the round errors *add* rather than compose, so a bound written as a
  product was wrong in the direction that flatters the system. The second was
  published in **0.5.1**, and also in 0.5.0: "`k` is the prover's round count and
  is not measured here, so no figure is quoted". `k` is supplied by the caller,
  the prover runs exactly that many sum-check rounds, the verifier checks the
  count, and the count does not depend on the field -- measured over an
  eight-bit and a 128-bit extension it is the same, which is the point. The
  extension field is the binding constraint rather than the round count: one
  round over eight bits already costs 2^-8, and no choice of `k` turns that into
  2^-128. The same false `k` claim appeared in eight places across both
  languages.

  Neither correction is enforced by a gate, and neither is measurable from the
  tree: a claim about soundness is arithmetic, and the only instrument is doing
  the arithmetic and writing down what it gave. The corrected statement is in
  `README.md`, `libs/stark/README.md`, `fuzz.zig` and the contract gate's own
  failure message, which are the places that describe current code.

  What was wrong with the corrections is also worth recording. `68645ec` fixed
  the 0.5.0 entries in place, which is a silent rewrite of a published record,
  and `bf7b300` then reverted only what `36ab1c7` had done, leaving the first
  rewrite in place. The revert reported "zero deleted lines" measured against
  `v0.5.1`, a base that already carried the damage, when the object was the
  content of the published 0.5.0 section, which means the tag `v0.5.0`.

254 tests in 30 steps.

- **`Transcript.squeezeField` read `F.order`, which exists in no field in this
  repository or in the pin.** It compiled only against test scalars that had
  invented one. It now derives the width from `F.MODULUS`, which every field
  carries, and `absorbField` checks for `toInt` where it uses it. Both functions
  called `traits.assertField` first, which asserts `inv`, `div`, `pow` and
  `isZero` and not the declarations they then read: a gate that accepts what it
  cannot support, and it failed one line after the guard meant to catch it.

- **`Circuit` and `Setup` in `snark` were not `pub`.** `verify` was reachable and
  `prove` was not, so the reference prover was unusable from anywhere but the file
  it is defined in. One word each; the tests did not notice because they are in
  that file.

- **The root package published a `zig-stark` module that did not compile.** The
  root duplicates each library's import wiring instead of delegating to its
  `build.zig`, and the copy was missing `zig-parallel`, so
  `StarkInner` could not find it. Nobody had compiled that module: every test goes
  through `libs/stark/build.zig`, which wires it correctly. `zig-parallel` is
  added, and `tests/published_api.zig` now instantiates the stack so the copy
  cannot rot unnoticed again. The duplication is still there and is the
  structural cause; closing it means making each library's build the only wiring,
  which is a packaging change and not one to make quietly in a bug fix.

- **The quick start in `libs/stark/README.md` verified as `false` with no error.**
  It created one channel and passed it to `prove` and then to `verify`. It also
  named `zs.m31.stark`, where `zs.m31` is the field and the namespace is
  `zs.stark`, and left `claimed_fib` as `...` rather than the last value of column
  0. Corrected in both languages, and the corrected version is what
  `consumer/src/main.zig` runs, so the example is executed rather than described.

### Measured

- **Round count of the sum-check, over two field pairs and two values of `k`.**
  Object: `proof.sumcheck.rounds.len` on a proof this repository's prover wrote,
  read from the proof rather than counted from a loop, so a prover that lied about
  its own round count would be caught. Fields: `Gf256/Gf256` and
  `Gf16/Gf2_128`, via `BiniusStark.prove` on the four-bit adder at the pin
  `zig-algebra 0.5.2`. Values of `k`: 3 and 6. Result: the rounds equal `k` in all
  four cases, and **do not depend on the field**, because `k` is supplied by the
  caller. So there is no single `k` to quote, and the extension field is the
  binding constraint rather than the round count: one round over eight bits
  already costs 2^-8, and no choice of `k` turns that into 2^-128. Tool: a
  temporary diagnostic, since removed -- which is why `tests/published_api.zig`
  now asserts the round count rather than leaving the figure with no witness.

- **Cost of a 128-bit extension over an eight-bit one.** Object: the
  `zig-stark-fuzz-tests` step, same gadget set and same round count on both
  fields, differing only in the field pair; measured as the per-step time
  `zig build test --summary all` prints, at two round counts so a constant offset
  would show up. Result: 20 rounds 4 s against 20 s, and 60 rounds 12 s against
  60 s. **5.0x in both, so the cost is linear in the rounds and not an offset.**
  Debug build, so the ratio is a proxy rather than the production figure.

### Not addressed here

- **`Schnorr.fromBytes` takes `[32]u8` and returns an error union, which no field
  in this tree matches**, so the generic Schnorr needs a wrapper to run on a real
  curve. Worse and separate: `challenge` swallows a decode failure with
  `catch Scalar.zero()`, turning a non-canonical digest -- a real attack, and the
  reason the pin returns an error union -- into the zero scalar. A signature with
  a zero scalar is an invalid signature the verifier rejects, or a valid
  signature of nothing. It is a `catch` that silences a security error, and it
  does not belong in the same commit as the other four, so it is left standing
  and recorded here.

- **The Binius convenience constructors all wire `CommittedMlePcsUnsafe`**, the
  variant that skips the 128-bit check, so the safe entry point is opt-in and the
  path of least resistance is unsound. Flipping all six was implemented and then
  reverted: it gates only the PCS layer, because `StarkInner` and
  `BiniusArgWith` hardcode `SumcheckUnsafe(E)`, and asking for eight bits through
  the checked PCS makes `error.FieldTooSmall` surface from inside `proveImpl`,
  whose `errdefer` at `binius/stark.zig:407` frees `lifted_cols[j]` from an
  uninitialised array and aborts with a general protection exception instead of
  propagating. Turning a silent bypass into a memory fault is worse than the
  state it replaces. It needs both layers, and the `errdefer` fixed on its own.

267 tests in 32 steps, six of them the published-API suite: new here, and run on every
`zig build test` rather than on demand.

## [0.5.1] - 2026-09-29

252 tests in 30 steps, up from 242 at 0.5.0 with no line of library source
touched: the diff since `v0.5.0` is nine files and none of them is under
`libs/*/src`. So this is a patch, and the measurement is the reason rather than a
side effect of it.

### Fixed
- **the documentation gate** walked the tree with `Dir.walk`, whose paths carry
  the platform's separator while every prefix in the gate is written with a
  forward slash, so on Windows it found almost nothing and reported success on
  two files. The build now sets the working directory of both gate steps, and
  both gates refuse to speak when they cannot see: the contract gate fails if it
  read no manifest, the documentation gate fails unless it finds the markers of a
  repository root and prints how many files it saw. A gate that shrinks its input
  and still reports green is worse than no gate, because it looks like a proof.
- **the documentation gate's own rules had no tests.** It ran only as an
  executable, so its rules were exercised only by whatever failure happened to
  come along. It has a test binary now, like the contract gate already had.
- **the test total in the architecture documents** was hand-written in two
  places, and went stale in one language while the other was corrected. It lives
  in the contract gate's ledger as a ratcheted constant now, with both documents
  checked against it, and both failure shapes have been seen to fail.
- **the Binius entries in the stark README** described one fuzz suite when there
  are three, two of them differing only in the field, and presented
  `core/hash` and `core/merkle` as settled when their adoption is an open
  question waiting on the same file-hash check the field layer took.

### Added
- **a second gadget fuzz pass** over a 128-bit extension, next to the fast one,
  with the default and the 2000 rounds untouched. The wide suite's claim is the
  narrow one: the 128-bit path gets random witnesses, not that it is sound.
- **`-Dfuzz-wide-iters`**, for the count of that pass. Each round is orders of
  magnitude costlier than the eight-bit one, which the repository already records
  as slow in a comment in the end-to-end tests.
- **a comparison of the tower's two multiplications**, which run depending on the
  host CPU. Its scope is written in the file rather than summarised anywhere
  else, because it cannot catch a defect both implementations share: agreement
  is not correctness.
- **a documentation rule for CJK in the prose.** A range, not a vocabulary, so
  it fires on the class and not on the strings already observed.

### Docs
- `docs/architecture` has a table of what a green run does not establish, with
  the four ways this repository has found one, and what closes each.
- The soundness bound on an eight-bit extension is stated as a sum and not a
  product in all eight places it appeared, and the per-round figure is gone: the
  rounds' errors add, so a narrow field is paid for once per round and no round
  count rescues it. `k` is the prover's round count and is not measured here, so
  no number is quoted. Binius commits in a bilinear algebra rather than a field,
  which the text now says rather than assuming a prime-field argument.

## [0.5.0] - 2026-09-28

See [SECURITY.md](SECURITY.md) for the soundness finding that this release
fixes. It is an advisory rather than a changelog line, and the reason is at the
end of that document.

### Changed (BREAKING)
- **zig-algebra** is pinned to `0.5.2`. The Blake3 in `libs/hash/src/blake3.zig`
  was not BLAKE3 at `0.5.1`: its root output recompressed the compressed state
  instead of the input chaining value, so the digest matched no canonical
  vector. This repository's transcript imports that hash, so **Fiat-Shamir
  challenges are not preserved across this upgrade**. A proof made under
  `<= 0.5.1` verifies under `<= 0.5.1` and does not verify after it, because
  the challenges changed. Commitments are unaffected and always were:
  `libs/stark/core/hash/hash.zig` wraps `std.crypto.hash.Blake3`.
- **stark/binius**: the local PCS and sum-check are gone. The sum-check was
  confirmed byte-identical to the adopted one over value, claimed sum and six
  rounds, by encoding both proofs and comparing bytes rather than comparing
  verdicts. The PCS was not, and the difference was real: our `commit` hashed
  every Merkle leaf twice, so its commitment was a different function and a
  proof from it was not readable by a verifier of the adopted one. Committed
  material from the previous version is not interchangeable.
- **stark/binius** call sites now name `SumcheckUnsafe` and
  `CommittedMlePcsUnsafe`. The field the Binius stack is instantiated over is
  `Gf256 = TowerField(3)`, eight bits wide, and the secure entry points require
  128 bits and refuse it. The name is in the code rather than in a comment so
  that it cannot be read as something it is not.
- **stark/core**: `pool.zig` is removed, along with its `Pool` struct, which was
  a copy of `zig-algebra`'s. `zig-parallel` is now a declared import.
- The Binius end-to-end suite is coverage of plumbing, not of soundness. A
  sum-check round's soundness error over an eight-bit field is of order 1/|F|,
  about 0.4%, and it composes over the rounds. See the ledger's `binius` revisit.

### Fixed
- **stark/core/hash** is pinned with known-answer vectors computed with an
  independent BLAKE3, one of which spans two chunks because the defect it
  guards against is in the multi-chunk path. `hash2`, which every Merkle
  internal node goes through, had no known-answer vector at all: it was only
  checked for differing from the concatenation of its arguments, which is a
  statement about this module and not about BLAKE3.
- **stark/binius** commitments are pinned with known-answer roots, also computed
  outside. A hash cannot be checked with itself, and a round trip agrees with
  itself, which is why the double hash survived every end-to-end test it had.

### Added
- **SECURITY.md**, the advisory for the challenge derivation, and its Spanish
  counterpart.

### Docs
- `libs/stark/README` no longer lists the files it does not have, and says where
  the sum-check and PCS come from now.

## [0.4.0] - 2026-09-27

MINOR: the asserts that guarded values a caller supplies return typed errors.

299 tests in 22 steps. Twenty-four asserts became twenty-three checks, and one
of them is not a conversion.

### Changed (BREAKING)
- **stark**: twenty-two asserts in the M31 zone and two in `core` now return
  errors instead of vanishing in ReleaseFast. `Univariate` returns
  `error.OutputLength` for a buffer of the wrong size and
  `error.InputLengthMismatch` when two inputs that must agree do not.
  `MerkleTree` returns `error.InvalidLeafCount` and `error.OutOfRange`.
  `CirclePoint.generatorWithOrder` and `CircleCoset.canonicHalf` return
  `error.InvalidLogSize`; both take a `log_size` that arrives from
  `StarkParams`, and 32 underflows the exponent shift. `fri` returns
  `error.InputLength` for a codeword whose length is not the domain's, which is
  the one the verifier is handed by the proof. The circle transforms return
  `error.OutputLength`, `error.InputLength` or `error.MismatchedLength`, kept as
  three because the name is the diagnosis the caller acts on.
- **stark**: `nttClassic` and `nttForward`/`nttInverse` return
  `error.InvalidLength`. Its two asserts said the same thing between them, and
  `isPowerOfTwo(0)` is already false, so one check covers the empty slice, an
  odd length and anything longer.

### Fixed
- **stark**: `circleEvalCoset` only compared `coeffs.len` against `evals.len`
  while the loop indexes the coset by the length of `evals`, so a short coset ran
  off the end of it and took the assert in `CircleCoset.at` with it. The caller
  got a failure pointing at the wrong file and the wrong reason. That is a check
  that was missing rather than one that was converted, and it only surfaced
  because the neighbouring asserts were being converted and their error paths
  exercised.
- **stark**: `simdButterfly`'s `a.len <= 2` is removed rather than converted. It
  delegated to `nttClassic` and was both redundant and weaker than the check in
  the function it called, since it accepted a length of zero. A redundant check
  weaker than its replacement is worse than none, because it reads as validation.
  The zone count therefore drops by three where two asserts were converted.

### Docs
- Two of the circle's asserts move to the invariant list in the contract ledger
  and are not converted. `CircleCoset.at` and `CircleDomain.get` take an index
  that every call site derives from the coset's own size, in a loop bounded by
  that size or as zero, so a bad index is not reachable from a caller and
  certainly not from a proof. Converting them would cascade a fallible signature
  through the NTT to guard a case that cannot happen.
- `primitiveRootOfUnity` is deliberately left, in `M31` twice and in `QM31` once.
  With `n == 0` the second check, `(n & (n - 1)) == 0`, underflows `n - 1`, so
  in ReleaseFast that is broken arithmetic producing a wrong root of unity rather
  than a missing diagnostic. It is the field arithmetic the prover uses on its
  hot path, and it needs its own analysis.
- `AGENTS.md` gained a rule to check the branch before editing, not after. Twice
  in two days a change was made on the wrong branch and the gate only noticed
  because an assert count came out impossible.

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
