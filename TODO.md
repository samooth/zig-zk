# TODO

> English. [Versión en español](TODO.es.md)

Open work, ordered by what closes the most use cases rather than by what is
easiest. Each item says what is missing and what "done" looks like, so it can be
checked rather than interpreted.

Nothing here is done. The checkbox is there to be ticked, not to decorate.

## Where each item stands

| Item | State |
|---|---|
| Complete the audit of `libs/signature` | a medias |
| Hash-to-curve | sin empezar |
| BLS12-381 | sin empezar |
| Schnorr multisignature and threshold | sin empezar |
| Ed25519 over a prime field | sin empezar |
| Point adapters for other curves | sin empezar |
| DER, PEM, and interchange formats | sin empezar |
| Propagate `allow_small_field` | done |
| The round count | medido, falta decidir |
| The root duplicates each library's wiring | a medias |
| Pin hygiene | hecho |
| `core/hash` and `core/merkle` | sin empezar |
| Constant-time claims, gated | sin empezar |
| Local branches | a medias |
| `libs/fri` in `zig-zkml` | precondición satisfecha |
| Hash inside the circuit | sin empezar |
| One repository | sin empezar |

- **a medias** — started, and the part that was done is written down below.
- **sin empezar** — nothing has been attempted.
- **medido, falta decidir** — the measurement exists and the number is settled;
  what is missing is a decision, and a decision is not a measurement.
- **precondición satisfecha** — the blocker that used to make it unmeasurable is
  gone. It can be started today and would produce a number.

---

## Security

- [ ] **Complete the audit of `libs/signature`** · *a medias*

  The library is three files -- `ed25519.zig`, `schnorr.zig` and `root.zig` -- and
  all three have been read. Two defects were found in the process, both in
  `SchnorrSignature`, and both are fixed.

  What is still missing is not the reading but the external reference: no scheme
  here has been compared against an implementation written independently from its
  specification, which is the check that would catch a misreading rather than an
  internal inconsistency.

  **Done:** every scheme has a test that compares against an implementation written
  from its specification, and a mutation that must be caught.

- [ ] **Hash-to-curve** · *sin empezar*

  Absent. Without it there is no identity scheme, and no construction that binds
  a message to a key in a verifiable way.

  **Done:** an RFC 9380 implementation for each curve the library signs on, with
  the published test vectors.

---

## Signature schemes

- [ ] **BLS12-381** · *sin empezar*

  Absent. The pin carries BLS12-381 pairing -- `libs/pairing/src/bls12_381.zig`
  was read to confirm it -- so the arithmetic the scheme needs does exist.

  This is the one that matters most: it is what makes aggregation possible, and
  the rest of this library assumes a field you can pair over. It is also the item
  that hash-to-curve blocks, which is the one ordering argument for putting
  hash-to-curve first.

  **Done:** aggregate signatures that verify as one, over the pinned pairing.

- [ ] **Schnorr multisignature and threshold** · *sin empezar*

  Absent. FROST or an equivalent is a whole use case that is not covered today:
  signing with a set of parties such that no single party holds the key.

  **Done:** `k` parties produce a signature that verifies under the single public
  key, and a mutation that breaks the Lagrange share is caught.

- [ ] **Ed25519 over a prime field** · *sin empezar*

  `std.crypto.sign.Ed25519` covers the 255-bit field variant. There is no Ed25519
  over BN254. For a ZKP library that is a real gap, and the curve is the one this
  library already does arithmetic over.

  **Done:** sign and verify over BN254 against the RFC 8032 test vectors, with the
  255-bit variant still delegating to std.

- [ ] **Point adapters for other curves** · *sin empezar*

  `root.zig` builds an adapter for secp256k1. There is no ready adapter for BN254,
  BLS12-381 or pasta inside this library. The `Point` contract is `add`,
  `scalarMul` and `eql`, plus a way to hash the point: either a `toBytes` method
  or public fields `x` and `y`. A curve that offers neither is rejected at compile
  time with a `@compileError` naming the type, which is the intended behaviour.

  **Done:** each named curve has an adapter, and the compile-error path has a test
  that shows a non-conforming point stopping the build rather than producing a
  challenge that omits the commitment.

---

## Encoding

- [ ] **DER, PEM, and interchange formats** · *sin empezar*

  Absent. `toBytes` returns `[65]u8` for a point, via `toUncompressedSec1`, and
  `[32]u8` for a scalar. Anything that needs to interoperate with another stack
  has to write the parser first.

  Boring, and required before anyone outside this repository can use the output.

  **Done:** a DER or PEM reader that rejects what it should, tested against another
  stack's bytes rather than against its own encoder.

---

## Binius

- [x] **Propagate `allow_small_field`** · *done*

  `StarkInner` and `BiniusArgWith` take a comptime `allow_small_field`, and each
  selects `Sumcheck` or `SumcheckUnsafe` **and** `MlePcs` or `MlePcsUnsafe`. Both
  layers together on purpose: a protocol that rejects in the sum-check and grinds
  in the commitment layer is worse than either being left alone.

  New entry points, so nothing existing moved: `BiniusStarkChecked(F, E, CP, bool)`,
  `BiniusStarkSecure(F, E)`, `BiniusArgChecked(F, E, CP, bool)`. The three old
  constructors pass `true` and are what they always were, which is why the test
  count was unchanged when this landed.

  **What the flag is not**, which took a failing assertion to establish: it does
  not make the configuration a different type. `SC` and `M` are declarations
  inside the struct, not fields, so two configurations differing only in the flag
  are the same type, and nothing stops a proof built under the safe sum-check
  being handed to a verifier built with the unsafe one. That is sound -- the proof
  format is identical and the unsafe verifier accepts more -- so it is a policy
  switch and not a type-level guarantee, and `sumcheck` / `mle_pcs` are published
  as types so the choice is inspectable rather than restated.

  **Still open, and it is the rest of this item:** whether the *default* moves is
  a product decision with 5.0x per round next to it. The flag makes the decision
  expressible; it does not make it.

---

## Build

- [ ] **The root duplicates each library's wiring** · *a medias*

  `build.zig` re-declares the module wiring instead of delegating to each
  library's own `build.zig`. The copy had drifted -- it was missing
  `zig-parallel`, which is fixed -- so the duplication is now equal rather than
  wrong, and that is not the same as gone.

  Rule 5 watches the symptom: a module wired into a build file that no source
  imports is a problem. The cause is the duplication, and closing it is a
  packaging change, not a bug fix.

  **Done:** `build.zig` names the five libraries and no module, so there is one
  place where a module can be added.

- [x] **Pin hygiene** · *hecho*

  `scripts/algebra-tags.txt` is the committed list of published tags, written by
  `zig build refresh-algebra-tags` and compared against upstream by `zig build
  check-pins-fresh`. Rule 6 in `check-contract` fails when the pin names a release
  nobody published, or is more than one release behind the newest.

  Two details that were not obvious. "One release behind" is a **position in the
  list**, not a subtraction: `zig-algebra` published no `v0.4.x` and no `v0.5.0`, so
  `0.6.0 - 0.5.3` is seven releases by minor-and-patch arithmetic and one by
  publication, and a version comparison would fail on a healthy repository. And the
  two network steps are deliberately **not** dependencies of `zig build test`, so the
  gate that runs offline and the gate that checks the reference are different steps
  on purpose.

  The failure this was for: the dead PRNG sat in four `zig-algebra` tags, three
  published and signed, and two repositories found out only when someone bumped the
  pin.

---

## Maintenance

- [ ] **`core/hash` and `core/merkle`** · *sin empezar*

  Copies of `zig-hash` and `zig-merkle`. They need the same file-hash
  verification that the field layer got. `core/merkle` carries a GPU accelerator
  hook that upstream does not -- `.auto` and `.on`, with `error.GpuUnavailable` --
  so there is a real maintenance cost in the decision.

  **Done:** each is diffed against upstream and the decision to keep or delete is
  written down with what diverged next to it.

- [ ] **Gate the constant-time claims, and keep the two doc strings honest** · *sin empezar*

  Two claims, and they are not the same kind of thing. Both were checked in the
  source before being written here, because "constant-time-ish" is exactly the shape
  of claim that cannot be refuted.

  `m31/circle/point.zig:mulScalar` is **not** constant-time and not through control
  flow: the window count is fixed, digit extraction is a shift and a mask, and there
  is no signed-digit representation, so no sign branch exists to leak. The leak is
  `table[digit]` -- a memory access at a secret-dependent index, a cache channel
  rather than a branch. Every call site in the tree passes a public scalar, so it is
  not reachable here. The doc string now says the mechanism and the reachability
  instead of hedging.

  **Done:** a gate that fails if a constant-time claim appears in a doc string or a
  comment without the mechanism named and the call sites checked. `mulScalar` and the
  non-constant-time note in `README.md` are the two specimens. That note says which
  call sites the limitation reaches -- verifying and public-witness proving are
  irrelevant, long-lived-secret proving and signing are not -- because a documented
  limitation otherwise reads as the reason it was not fixed, and a reader cannot tell
  a decision from a delay.

- [ ] **Local branches** · *a medias*

  `backup-pre-rewrite` and `rebuild-OLD` point at the same commit, so one of them
  is redundant by inspection. `backup-pre-rewrite-0.5.0` is the only copy of the
  history rewritten before 0.5.0. `salvage-50cb942` has served its purpose, and
  the source it held was confirmed identical to what was rebuilt.

  **Done:** the redundant branch is deleted and the one that is genuinely unique
  is either kept deliberately or released, with the choice written down.

---

## Outside this repository

These are not this repository's work. They are listed because they block it.

- [ ] **`libs/fri` in `zig-zkml`** · *precondición satisfecha*

  614 lines of a private FRI implementation. The question is whether to delete it
  and use the `zig-algebra` one, or keep it. The line count is the only figure here
  with no object to check it against in this workspace.

  The two pinned code paths that did not complete are fixed in `zig-algebra 0.6.0`,
  and the pin moved here in the same release. Bumping the pin is what makes the
  decision measurable rather than a matter of opinion.

  **Done:** the two implementations are diffed and the decision is written down.

- [ ] **Hash inside the circuit** · *sin empezar*

  Not started. Nothing else on any circuit roadmap is reachable without it: a
  circuit that cannot hash cannot prove a preimage.

  Poseidon first. It is written generically over a field and uses only additions
  and constant multiplications, which is why it is cheap in a circuit. The others
  are not, and should not be promised in the same breath.

  **Done:** Poseidon constrained in-circuit, with a gadget test that a wrong digest
  cannot satisfy.

- [ ] **One repository** · *sin empezar*

  Five libraries, five `build.zig.zon`, and one version for the project: the root
  is `0.7.0` and every library is `0.1.0`. There is one changelog, in two
  languages, covering all five.

  Whether they share a history is still open, and it is a smaller decision than it
  looks precisely because the libraries are at `0.1.0`, where no compatibility is
  owed to anyone, and the root's own `0.x` line is the only thing a consumer can
  currently pin to.

  **Done:** one history, or a written reason there are several.
