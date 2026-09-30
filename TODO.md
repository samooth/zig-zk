# TODO

> English. [Versión en español](TODO.es.md)

Open work, ordered by what closes the most use cases rather than by what is
easiest. Each item says what is missing and what "done" looks like, so it can
be checked rather than interpreted.

---

## Security

### Complete the audit of `libs/signature`

The library is three files -- `ed25519.zig`, `schnorr.zig` and `root.zig` -- and
all three have been read. Two defects were found in the process, both in
`SchnorrSignature`, and both are fixed.

What is still missing is not the reading but the external reference: no scheme here
has been compared against an implementation written independently from its
specification, which is the check that would catch a misreading rather than an
internal inconsistency.

Done means: every scheme has a test that compares against an implementation written
from its specification, and a mutation that must be caught.

### Hash-to-curve

Absent. Without it there is no identity scheme, and no construction that binds
a message to a key in a verifiable way.

Done means: a RFC 9380 implementation for each curve the library signs on, with
the published test vectors.

---

## Signature schemes

### BLS12-381

Absent. The pairing is already implemented in `zig-algebra`, so the arithmetic
the scheme needs exists.

This is the one that matters most: it is what makes aggregation possible, and
the rest of this library assumes a field you can pair over.

### Schnorr multisignature and threshold

Absent. FROST or an equivalent is a whole use case that is not covered today:
signing with a set of parties such that no single party holds the key.

### Ed25519 over a prime field

`std.crypto.sign.Ed25519` covers the 255-bit field variant. There is no
Ed25519 over BN254. For a ZKP library that is a real gap, and the curve is
the one this library already does arithmetic over.

### Point adapters for other curves

`root.zig` builds an adapter for secp256k1. There is no ready adapter for
BN254, BLS12-381 or pasta inside this library. The `Point` contract is `add`,
`scalarMul` and `eql`, plus a way to hash the point: either a `toBytes` method or
public fields `x` and `y`. A curve that offers neither is rejected at compile time
with a `@compileError` naming the type, which is the intended behaviour, and it is
the behaviour that `libs/signature/README.md` documents.

---

## Encoding

### DER, PEM, and interchange formats

Absent. `toBytes` returns 65 bytes for a point and `[32]u8` for a scalar.
Anything that needs to interoperate with another stack has to write the parser
first.

Boring, and required before anyone outside this repository can use the output.

---

## Binius

### Propagate `allow_small_field`

`StarkInner` and `BiniusArgWith` still hardcode `SumcheckUnsafe(E)` at
`stark.zig:83` and `arg.zig:48`, and the six convenience constructors still
select `CommittedMlePcsUnsafe`.

Done means: the flag reaches both layers, and the default can then be decided
on measured cost rather than on the shape of the code.

### The round count

`proof.sumcheck.rounds.len` is `k`, and `k` is measured at 3 for
`Gf256/Gf256` and 6 for `Gf16/Gf2_128`. The bound is `k/|E|`, and 128 bits
cost 5.0x per round, linear in the fuzz suite.

What is missing is the decision: whether the default moves to 128 bits is a
product decision, and it needs to be written down with that number next to it.

---

## Build

### The root duplicates each library's wiring

`build.zig` re-declares the module wiring instead of delegating to each
library's own `build.zig`. The copy had drifted -- it was missing `zig-parallel`,
which is fixed -- so the duplication is now equal rather than wrong, and that is
not the same as gone.

Rule 5 watches the symptom: a module wired into a build file that no source
imports is a problem. The cause is the duplication, and closing it is a
packaging change, not a bug fix.

### Pin hygiene

Nothing checks that `build.zig.zon` matches the published tags of
`zig-algebra`.

The same failure happened once already. Measured by tag, the dead PRNG is in
four tags -- `v0.5.0`, `v0.5.1`, `v0.5.2`, `v0.5.3` -- of which three were
published and signed, and the fix is later than all four. The other two
repositories found out only when someone bumped the pin. That was sustained by
`zig-rng` being wired into four `build.zig` files with zero imports outside
`libs/rng`, which is what Rule 5 now fails on.

Done means: a gate that fails when a pin is more than one release behind. It needs
a source of truth for the published tags, which does not exist yet -- that is the
part that has to come first, since a threshold with no tag list to compare against
is not a gate.

---

## Maintenance

### `core/hash` and `core/merkle`

Copies of `zig-hash` and `zig-merkle`. They need the same file-hash
verification that the field layer got. `core/merkle` carries a GPU accelerator
hook that upstream does not, so there is a real maintenance cost in the
decision.

### Local branches

`backup-pre-rewrite` and `rebuild-OLD` point at the same commit.
`backup-pre-rewrite-0.5.0` is the only copy of the history rewritten before
0.5.0. `salvage-50cb942` has served its purpose.

---

## Outside this repository

These are not this repository's work. They are listed because they block it.

### `libs/fri` in `zig-zkml`

614 lines of a private FRI implementation. The question is whether to delete
it and use the `zig-algebra` one, or keep it.

The two pinned code paths that did not complete are fixed in
`zig-algebra 0.6.0`. Bumping the pin is what makes the decision measurable
rather than a matter of opinion.

### Hash inside the circuit

Not started. Nothing else on any circuit roadmap is reachable without it: a
circuit that cannot hash cannot prove a preimage.

Poseidon first. It is written generically over a field and uses only additions
and constant multiplications, which is why it is cheap in a circuit. The others
are not, and should not be promised in the same breath.

### One repository

Five libraries, five `build.zig.zon`, and one version for the project: the root is
`0.7.0` and every library is `0.1.0`. There is one changelog, in two languages,
covering all five. Whether they share a history is still open, and it is a smaller
decision than it looks precisely because the libraries are at `0.1.0`, where no
compatibility is owed to anyone, and the root's own `0.x` line is the only thing a
consumer can currently pin to.