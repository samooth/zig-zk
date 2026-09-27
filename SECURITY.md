# Security advisory: Fiat-Shamir challenges were not derived from BLAKE3

> English. [Versión en español](SECURITY.es.md)

**Affected:** zig-zk `0.1.0` through `0.4.0`, that is, every version built
against `zig-algebra` at pin `<= 0.5.1`.

**Fixed in:** the next release, by pinning `zig-algebra` `0.5.2`.

**Severity:** the emitted artefacts are not valid under the analysis the
protocol describes. We could not determine from outside whether that is
exploitable, and not knowing is the finding.

## What happened

The Blake3 implementation in `zig-algebra`'s `libs/hash/src/blake3.zig` was not
BLAKE3. Its root output recompressed the *compressed state* of the last chunk
instead of the *input chaining value* and the original block, which is what
BLAKE3's reference does. The chaining values of non-root nodes came from a
correct path, so the deviation was confined to the final digest, and the
compression function, the IV, the message schedule and the domain-separation
flags were all BLAKE3. The result was deterministic and self-consistent, and it
matched no canonical vector:

| input | `zig-algebra` at 0.5.1 | BLAKE3 |
|---|---|---|
| empty | `5691d858…` | `af1349b9…` |
| `abc` | `605a5b03…` | `6437b3ac…` |

`zig-algebra` `v0.5.2` fixes it. The fix recompresses with the input chaining
value, which is why the reference implementation keeps that value and the block
around in its output struct.

## What this repository was doing with it

`libs/transcript/src/transcript.zig` imports `@import("zig-hash").Blake3`, so
every Fiat-Shamir challenge this repository derived came from that function. A
transcript is a Blake3 sponge and the challenges are squeezes out of it, so the
challenges in the proofs `0.1.0` through `0.4.0` emitted are not the challenges
the protocol specifies.

The commitments were **not** affected, and this is worth separating because the
two travel together. `libs/stark/core/hash/hash.zig` wraps
`std.crypto.hash.Blake3`, and the Merkle in `core/merkle` uses it, so every
commitment this repository made was BLAKE3 throughout. Only the challenges were
not.

## What it means for a proof you already have

- A proof made under pin `<= 0.5.1` **verifies** under that same pin. The
  function is deterministic, so a verifier running the same code derives the
  same challenges, and nothing about the artefact is detectably malformed.
- That same proof **does not verify** after upgrading to `0.5.2`, because the
  challenges changed. That is the ordinary consequence of changing a hash.
- The security arguments written for these STARKs assume a Blake3 sponge. They
  do not apply to the software as it was distributed.

We can bound the damage somewhat: the deviation is in the root output only, so
the intermediate chaining values, and therefore the structure of the commitments
and of the Fiat-Shamir transcript, were computed correctly. A practical break
seems unlikely. We did not prove it, and this advisory is not a certification of
soundness: a release cannot be certified by the party that cannot see the
defect.

## How it was found

By a differential harness that compared the local PCS against the adopted one by
**encoding both proofs and comparing bytes**, on random witnesses. A comparison
of verdicts would have shown nothing: both sides verify their own artefact
happily, so a shared defect looks like agreement. The bytes differed, the
difference was localised to the Merkle paths, and following it turned up a second
defect in this repository — a leaf hashed twice — plus the wrong hash underneath.

The instrument that made the rest possible was a known-answer vector computed
with an **independent** BLAKE3, in Python. A hash cannot be checked with itself,
so the vectors in `libs/stark/core/hash/hash.zig`, one of which spans two chunks
because the defect is in the multi-chunk path, are the only thing in this
repository that can see a wrong hash.

## What to do

Upgrade the pin. The change is mechanical:

```
zig build --fetch
zig build test --summary all
```

No source change is required, and no proof format changed beyond the challenges
described above.

The same finding is reported against `zig-algebra`, which cannot see it from
inside: the same blindness runs the other way, since from here nobody saw that
the transcript imported the hash at all. Each of the two advisories is written
from what its own repository can attest, and each points at the other.

## Why this is an advisory and not a changelog line

A soundness finding buried in a changelog is a security finding nobody looks for.
This repository has one already, in more than one form: a release note asserting
a publication, a self-generated vector indistinguishable from a real one, a KAT
discipline that existed as a practice and was not on any list. A claim in prose
expires; a test that runs does not.
