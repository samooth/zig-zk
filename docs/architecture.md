# zig-zk Architecture Documentation

## Overview

`zig-zk` is a monorepo of cryptographic protocol libraries built on `zig-algebra`. It provides the protocol layer: Fiat-Shamir transcripts, commitment schemes, signature schemes, STARKs, and SNARKs.

## Architecture

```
External: zig-algebra (v0.1.0+)
    │
Layer 1: transcript          (Fiat-Shamir)
    │
Layer 2: commitment          (KZG, FRI, IPA, Merkle, DARK)
    │
Layer 3: signature, air      (signatures, AIR framework)
    │
Layer 4: stark, snark        (full proof systems)
```

## Protocol Design Principles

### 1. Algebraic Abstraction

All protocols are generic over algebraic structures from `zig-algebra`:

```zig
// Transcript works over any Field trait
pub fn Transcript(comptime F: type) type {
    // F must satisfy FieldTrait
}

// Commitment schemes work over any curve with PairingFriendly
pub fn KZG(comptime Curve: type) type {
    // Curve must satisfy PairingFriendlyTrait
}

// STARK works over any field with NTT
pub fn Stark(comptime F: type) type {
    // F must satisfy FieldTrait + NttTrait
}
```

### 2. Fiat-Shamir Transform (transcript)

Two transcript variants:

**`Transcript`** - Core absorb-squeeze:
- `absorb(bytes)` - absorb raw bytes (length-prefixed)
- `absorbField(F, element)` - absorb field element (32-byte LE)
- `squeeze(out)` - squeeze challenge bytes
- `squeezeField(F)` - squeeze field element (rejection sampling)
- `squeezeU64()/squeezeU256()` - integer challenges
- `clone()` - fork transcript state
- `reset(label)` - restart with same domain separator

**`LabelledTranscript`** - Domain-separated:
- Every operation prefixed with string label
- Prevents cross-protocol attacks
- Same API with explicit labels

**`Channel`** - Duck-typed (zig-stark style):
- Absorbs any type with `SIZE`/`toBytes`/`fromBytes`
- Built-in `sampleIndex(n)` for uniform indices
- Simpler, no field trait required

### 3. Commitment Schemes (commitment)

Multiple schemes in one library:

| Scheme | Basis | Requirements | Use Case |
|--------|-------|--------------|----------|
| **Merkle** | Hash tree | `hash` | General purpose |
| **KZG** | Pairing | `field` + `pairing` | Polynomial commitments |
| **IPA** | Curve | `curve` | Inner product args |
| **FRI** | NTT + Merkle | `field` + `ntt` + `merkle` | STARKs |
| **DARK** | Class groups | `field` + `linalg` | Transparent setup |
| **Ligero** | Hash only | `hash` | Transparent setup |

**Pedersen commitments** - also in commitment:
- Generic over any Point type
- Homomorphic: `commit(a) + commit(b) = commit(a+b)`
- Vector commitments with generators

**Shamir Secret Sharing** - also in commitment:
- Generic over any Scalar type
- Lagrange interpolation
- VSS commitments

**Sigma Protocols** - also in commitment:
- Schnorr Proof of Knowledge
- CDS OR Proof (1-out-of-N)

### 4. Signatures (signature)

Signature schemes over elliptic curves:

| Scheme | Curve | Features |
|--------|-------|----------|
| **Schnorr** | Any | Batch verify, threshold |
| **ECDSA** | Secp256k1 | Bitcoin/Ethereum |
| **Ed25519** | Ed25519 | Fast, deterministic |
| **BLS** | BLS12-381 | Aggregation |
| **MuSig2** | Secp256k1 | Multi-sig, 2-round |

### 5. AIR Framework (air)

Generic Algebraic Intermediate Representation:

```zig
const MyAir = Air(F, PublicInputs);

// Define constraints
const constraint: MyAir.Constraint = .{
    .degree = 2,
    .evaluate = myTransitionConstraints,
};

// Define boundary conditions
const boundary: MyAir.Assertion = .{
    .column = 0,
    .step = 0,
    .value = F.one(),
};
```

Components:
- `EvaluationFrame` - current/next row pair
- `BoundaryConstraint` - fixed values at steps
- `TransitionConstraint` - polynomial relations
- `ExecutionTrace` - full trace matrix

### 6. STARK (stark)

Two full STARK stacks:

**M31 Stack** (Circle FFT):
- Prime field M31 (2^31 - 1)
- Circle FFT for NTT
- DEEP-FRI optimization
- Full prover/verifier

**Binius Stack** (Binary fields):
- Tower fields GF(2) → GF(2^128)
- Sum-check protocol
- Packed MLE evaluation
- FRI-PCS for binary fields
- Recursive verification

### 7. SNARK (snark)

Multiple SNARK protocols:

| Protocol | Setup | Proof Size | Recursion |
|----------|-------|------------|-----------|
| **Groth16** | Trusted | 3 group elements | No |
| **PLONK** | Universal | ~2KB | No |
| **Marlin** | Universal | ~2KB | No |
| **Halo2** | None | Variable | Yes |
| **Nova** | None | Folding | Yes |

## Dependency Management

### zig-zk depends on zig-algebra

```zig
// build.zig.zon
.{
    .dependencies = .{
        .zig_algebra = .{
            .url = "https://github.com/samooth/zig-algebra/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "946d91e533bcdc12dd20c63970bf2026dd97bd041ce38e35dec672bf3a462b91",
        },
    },
}
```

### Importing modules

```zig
const algebra = b.dependency("zig_algebra", .{});

// Use specific modules
const field_mod = algebra.module("zig-field");
const curve_mod = algebra.module("zig-curve");
const ntt_mod = algebra.module("zig-ntt");
const merkle_mod = algebra.module("zig-merkle");
const pairing_mod = algebra.module("zig-pairing");
```

## Testing

```bash
# Individual library
cd libs/transcript && zig build test

# All libraries
zig build test
```

## Security Considerations

### Fiat-Shamir Soundness

- All transcripts use domain separation
- Counter-based challenge derivation prevents replay
- Blake3 XOF for extendable output

### Constant-Time Operations

- Rejection sampling for uniform field elements
- Montgomery arithmetic for constant-time field ops
- CLMUL for constant-time binary field multiplication

### Domain Separation

- All protocols use unique domain strings
- Labels prefixed on every transcript operation
- Hash-to-curve uses RFC 9380 with domain

## Versioning

All libraries versioned together at workspace level (v0.1.0). Depends on `zig-algebra` v0.1.0+.

## Contributing

1. Protocol libraries go in `libs/`
2. Each library must specify its `zig-algebra` deps
2. Add tests for new protocols
3. Keep comptime-only where possible
4. Document algebraic requirements in doc comments
5. Run full test suite: `zig build test`