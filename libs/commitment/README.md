# zig-commitment

Polynomial and vector commitment schemes for zero-knowledge proofs. Currently implements IPA (Inner Product Argument) and Pedersen commitments.

## Features

- **IPA (Inner Product Argument)** — Bulletproofs-style logarithmic proof of `<a, b> = c`
- **Pedersen commitment** — `commit(v, r) = v*G + r*H` with homomorphic operations
- **Pedersen VSS (Verifiable Secret Sharing)** — polynomial commitments for distributed key generation
- **Generic over field and curve** — works with any prime field and elliptic curve
- **No allocations** in the hot path

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_commitment = .{
        .path = "path/to/zig-algebra-core/zig-commitment",
    },
},
```

Then in your `build.zig`:

```zig
const zc = b.dependency("zig_commitment", .{});
exe.root_module.addImport("zig-commitment", zc.module("zig-commitment"));
```

## Quick Start

### IPA (Inner Product Argument)

```zig
const zc = @import("zig-commitment");
const F = @import("zig-field").BN254_Fp;

// Create IPA prover
var ipa = try zc.Ipa(F).init(allocator, 64, seed);
defer ipa.deinit();

// Compute inner product
const c = zc.Ipa(F).innerProduct(&a, &b);

// Prove and verify
const proof = try ipa.prove(allocator, &a, &b, c);
defer proof.deinit(allocator);
try ipa.verifyWithCommitment(commitment, &proof);
```

### Pedersen Commitment

```zig
// Commit to a value with blinding
const commitment = zc.pedersen.commit(value, blinding, G, H);

// Verify opening
try std.testing.expect(zc.pedersen.verify(commitment, value, blinding, G, H));

// Homomorphic addition: commit(a) + commit(b) = commit(a + b)
const sum = commitment_a.add(commitment_b);
```

## API

| Function | Description |
|----------|-------------|
| `Ipa(F).init(allocator, n, seed)` | Create IPA prover for 2^n elements |
| `Ipa(F).innerProduct(a, b)` | Compute `<a, b>` |
| `Ipa(F).prove(allocator, a, b, c)` | Generate IPA proof |
| `Ipa(F).verifyWithCommitment(commitment, proof)` | Verify proof against commitment |
| `pedersen.commit(v, r, G, H)` | Pedersen commitment |
| `pedersen.verify(C, v, r, G, H)` | Verify Pedersen opening |
| `pedersen.add(C1, C2)` | Homomorphic addition |
| `pedersen.sub(C1, C2)` | Homomorphic subtraction |

## Running Tests

```bash
zig build test
```

## Design Notes

- IPA uses Bulletproofs-style logarithmic communication (O(log n) field elements)
- Pedersen commitments are information-theoretically hiding and computationally binding
- The IPA implementation operates over field elements; the Pedersen module operates over curve points
- Future: KZG, FRI, DARK, Ligero commitments

## License

MIT OR Apache-2.0
