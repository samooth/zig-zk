# Security advisory: Fiat-Shamir challenges were not derived from BLAKE3

> English. [Versión en español](SECURITY.es.md)

**Advisory 1 of 2 -- see below.**

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

---

# Security advisory: Schnorr challenges were mostly zero, and never bound the key

**Affected:** `libs/signature`, the generic `SchnorrSignature(Point, Scalar)`, as
published in `0.6.0` and every version before it.

**Fixed in:** the next release. `0.6.0` is affected and this advisory is part of
what the next one carries.

**Severity:** four signatures in five do not commit to the key or the message, and
anyone can produce a valid signature without a private key.

Ed25519 is **not** affected. It is delegated to `std.crypto.sign.Ed25519` and
never goes through `SchnorrSignature`. "The signature library is broken" and
"half of it is" are different claims, and this is the second.

## A correction to the 0.6.0 record, written after the tag

`0.6.0`'s changelog records this as "irrepetibilidad rota", in the shared terms
of the "not addressed here" section, and defers it to `0.6.1`. That is an
understatement by omission, and the tag is signed so it cannot be rewritten. It
omits two things:

- **four signatures in five**, not a rare case -- `P(rejection) = 0.810969`, so
  the expected count is 4.05 in 5;
- **two different messages produce the same signature byte for byte**, because
  with `e = 0` the message never reached the arithmetic.

A signed tag that understates a P0 is worse than one that omits it, because a
reader decides on the number in front of them. So this note exists, and it does
not wait for a version name: it is true now, and whoever reads the changelog
afterwards will find it here.

The next release will carry the changelog entry that states all of it.


## Two defects, independent

**The challenge was zero four times out of five.** The code was

```zig
return Scalar.fromBytes(digest) catch Scalar.zero();
```

For a field narrower than the digest, a digest is out of range most of the time.
The BN254 scalar field is 254 bits and a SHA-256 digest is 256, so the draw
exceeds the modulus **81.1%** of the time — measured, not estimated:

```
P(digest >= modulus) = 1 - 21888242871839275222246405745257275088548364400416034343698204186575808495617 / 2^256
                     = 0.810969
```

Verification is `s*G == R + e*P`. With `e = 0` that is `s*G == R`, which anyone
satisfies by choosing `r`, setting `R = r*G` and `s = r`. No private key is
involved anywhere. The demonstration is in the suite and uses no secret.

It is worse than a forgeable signature: `e = 0` means the message never reached
the arithmetic, so **two different messages produce the same signature byte for
byte**. That is not a weak signature, it is an absent one.

**The challenge never contained the key.** `hashPoint` tested

```zig
if (@hasDecl(Point, "toBytes")) { ... }
else if (@hasDecl(Point, "x") and @hasDecl(Point, "y")) { ... }
```

`@hasDecl` reports declarations, not struct fields. `x` and `y` on an affine
point are fields. So the second branch could never be taken by any type at all,
and a point without a `toBytes` declaration had both branches false and hashed
**nothing** — no base point, no public key, no nonce commitment.

## Why the suite passed

The fixtures chose values that made the defects invisible, which is the fifth
time in this repository that a test caught nothing for that reason.

The fixture in `schnorr.zig` was a scalar of modulus 7 whose `fromBytes` read a
single byte and **could not fail**. No rejection, so no challenge of zero.

The other instantiation, in `root.zig`, is secp256k1, whose scalar order sits just
below `2^256`. A random 32-byte digest is below it almost always — the rejection
probability is `(2^256 - n) / 2^256 = 3.73e-39`, about `2^-127` — so that one is
invisible to defect two as well.

So between them, every instantiation in the repository sat where the defects
could not show. The rule that follows, and which belongs next to the others in
`AGENTS.md`: **a fixture has to choose the value that makes the defect visible,
not the one that makes the test easy.** A small modulus means the real arithmetic
never runs.

## What the fix is, and why it is a compile-time change

`@hasDecl` became `@hasField`, and a point that can be hashed by neither route is
now a `@compileError` rather than a group that quietly verifies signatures without
the key in the hash.

## The `catch` rule these two defects came out of

Three `catch` expressions are left in this library, and the difference between the
wrong one and the right one is not style, it is the kind of thing being computed.

- **`catch Scalar.zero()` on a challenge.** The value feeds `s*G == R + e*P`.
  Turning an error into a value puts `0` into arithmetic, and `0` there is the
  forgery condition. Wrong.
- **`catch return false` on `ed25519.verify`.** It is a predicate. `false` is the
  answer whether the signature is invalid or the parse failed, so the catch
  changes nothing an attacker can observe. Right.
- **`catch { assert; unreachable; }` on the secp256k1 adapter's `scalarMul`.** It
  never produces a value, so there is no wrong answer left in it. Right, and it
  was `catch Secp256k1.identityElement` until this review: the identity is what
  makes Schnorr degenerate, so a value-returning catch here is the same defect as
  the first one.

The test to apply is not "does the catch swallow an error" but **what does the
result become.** If it becomes a value that later arithmetic reads, a catch that
converts an error into that value is a defect. If it becomes a predicate's answer
or produces no value at all, it is not. Same operation, two contexts, and the
safety depends on the context.

The challenge is reduced through `Scalar.fromInt` instead of parsed with
`fromBytes`. `fromInt` reduces and has no error to swallow, so `catch` is gone
and the failure cannot be reintroduced by that line. Parsing was the wrong
contract for a digest in the first place: a 32-byte digest is a uniform draw, not
an encoding.

Three regression tests, each confirmed by mutation on the real code: the
challenge is not zero, and it differs when the public key, `R`, the base point or
the message differ. The last one is the assertion that was missing and it is the
one that matters — an implementation that bound the key but not `R` would still
allow a nonce to be reused.

## Why this is an advisory and not a changelog line

Because a forgeable signature read in a changelog is a security finding nobody
looks for. `0.6.0` recorded this as "irrepetibilidad rota" and scheduled it for
`0.6.1`, which reads as routine work. It was found from outside, by someone
building a demo over web/wasm, in a file where every test had always passed.
