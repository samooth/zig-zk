# zig-commitment

> English. [Versión en español](README.es.md)

Commitment schemes for zero-knowledge proofs: the inner product argument,
Pedersen commitments, Shamir secret sharing, and two Σ-protocols.

## Features

- **IPA (Inner Product Argument)** — a Bulletproofs-style logarithmic-size proof
  that `⟨a, b⟩ = c`, with the challenges bound by a running Fiat-Shamir sponge
- **Pedersen commitments** — `commit(v, r) = v·G + r·H`, homomorphic under
  addition, generic over any point type
- **Shamir secret sharing** — split a secret into shares and reconstruct it with
  Lagrange interpolation, generic over the scalar type
- **Σ-protocols** — `SchnorrPoK` (proof of knowledge) and `CdsOrProof` (CDS '94
  one-out-of-many OR proof)
- **Generic** — everything is parameterised by the field or point type
- **`MerkleTree`** — re-export of `zig-merkle`

The prover and verifier take an explicit allocator: the argument keeps the
challenge transcript and the folded vectors, so this library allocates by design
and frees everything on `deinit`.

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.2.2.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-commitment", zk.module("zig-commitment"));
```

## Quick Start

### IPA (Inner Product Argument)

`n` is the number of elements and **must be a power of two**; `init` returns
`error.LengthNotPowerOfTwo` otherwise. Verification needs the commitment, not
just the inner product: the value `⟨a, b⟩` alone does not pin down a unique pair
of committed vectors.

```zig
const zc = @import("zig-commitment");
const zf = @import("zig-field");

// n = 8 elements, generators derived from the seed
var seed: [32]u8 = undefined;
std.mem.writeInt(u64, seed[0..8], 42, .little);
var ipa = try zc.Ipa(zf.M31).init(allocator, 8, seed);
defer ipa.deinit();

const c = zc.Ipa(zf.M31).innerProduct(a, b);
const C = ipa.commit(a, b, c);

const proof = try ipa.prove(allocator, a, b);
defer proof.deinit(allocator);
try ipa.verify(C, &proof);   // errors on a mismatch
```

### Pedersen commitments

```zig
const P = zc.Pedersen(MyPoint, MyScalar);

const commitment = P.commit(value, blinding, G, H);
try std.testing.expect(P.verify(commitment, value, blinding, G, H));

// Homomorphic: commit(a) + commit(b) = commit(a + b)
const sum = commitment_a.add(commitment_b);
const diff = commitment_a.sub(commitment_b);
```

### Shamir secret sharing

```zig
const S = zc.shamir.Share(MyScalar);

const shares = try zc.shamir.split(allocator, secret, threshold, total, rng);
const rebuilt = zc.shamir.reconstruct(MyScalar, shares);
```

## API

### `Ipa(F)`

| Function | Description |
|----------|-------------|
| `Ipa(F).init(allocator, n, seed)` | Create the argument; `n` elements, power of two |
| `Ipa(F).innerProduct(a, b)` | Compute `⟨a, b⟩` |
| `ipa.commit(a, b, c)` | Commit to the pair with the inner product `c` |
| `ipa.prove(allocator, a, b)` | Produce the proof |
| `ipa.verify(commitment, *proof)` | Verify against the commitment; errors on failure |
| `proof.deinit(allocator)` | Release the proof |
| `ipa.deinit()` | Release the generators |

### `Pedersen(Point)`

| Function | Description |
|----------|-------------|
| `P.commit(value, blinding, G, H)` | `value·G + blinding·H` |
| `P.verify(C, value, blinding, G, H)` | Check an opening |
| `P.add(C1, C2)` | Homomorphic addition |
| `P.sub(C1, C2)` | Homomorphic subtraction |

### `shamir`

| Function | Description |
|----------|-------------|
| `shamir.Share(Scalar)` | The share type |
| `shamir.split(allocator, secret, threshold, total, rng)` | Split into `total` shares |
| `shamir.reconstruct(Scalar, shares)` | Rebuild from `threshold` or more |
| `shamir.lagrangeCoefficient(...)` | Interpolation coefficient |

### Sigma protocols

| Function | Description |
|----------|-------------|
| `SchnorrPoK(Point, Scalar).prove(...)` | Schnorr proof of knowledge |
| `CdsOrProof(Point, Scalar).create(...)` | CDS '94 one-out-of-many OR proof |
| `CdsOrProof(Point, Scalar).verify(...)` | Verify an OR proof |

## Running Tests

```bash
zig build test --summary all
```

## Design Notes

- The IPA challenges come from a **running** Blake3 sponge: it absorbs the
  generators, `n` and the commitment before the first round, and every round's
  response afterwards. Deriving the challenges from a static state would leave
  the argument malleable.
- Absorbed values are length-prefixed, so distinct transcripts cannot be reached
  by splitting or concatenating inputs differently.
- Verification replays the sponge rather than re-deriving anything from the
  proof, so a proof cannot be replayed under a different statement.
- Pedersen commitments are perfectly hiding and computationally binding, given
  a discrete-log assumption on the generators.

## License

MIT or Apache-2.0
