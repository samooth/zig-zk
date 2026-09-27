# zig-signature

> English. [Versión en español](README.es.md)

Digital signatures. Two schemes: a generic Schnorr that works over any elliptic
curve, and Ed25519 delegated to the standard library.

## Features

- **Generic Schnorr** — `SchnorrSignature(Point, Scalar)` over any group with
  `add`, `scalarMul`, `eql` and any scalar type with `fromBytes`, `zero`, `add`
  and `mul`. Signature and verification are five lines; everything interesting
  is in the caller choosing the curve.
- **Ed25519** — a thin re-export of `std.crypto.sign.Ed25519`, which is
  deterministic, constant time and already audited. Nothing here reimplements
  it, because the parts that matter (nonce derivation, scalar clamping,
  cofactorless verification) are the parts that are easy to get subtly wrong.
- **secp256k1 adapters** — `libs/signature/src/root.zig` adapts
  `std.crypto.ecc.Secp256k1` points and scalars to the generic interface, which
  is what makes Schnorr usable on Bitcoin's curve.

Not implemented: ECDSA and BLS. Ed25519 is delegated rather than written, and
the same reasoning should apply to anything else the standard library already
provides.

## Installation

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.3.0.tar.gz",
        .hash = "...",
    },
},
```

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-signature", zk.module("zig-signature"));
```

## Quick Start

### Generic Schnorr

```zig
const sig_lib = @import("zig-signature");

// Point needs: add, scalarMul, eql
// Scalar needs: fromBytes, zero, add, mul
const Sig = sig_lib.SchnorrSignature(MyPoint, MyScalar);

// Sign: R = k*G, e = H(G, P, R, msg), z = k + e*x
const signature = Sig.init(R, z);

// Verify: z*G == R + e*P
if (!signature.verify(G, public_key, "message")) return error.BadSignature;
```

`challenge(base, public_key, R, msg)` is exposed so a caller can derive the
challenge with its own hash.

### Ed25519

```zig
const s = @import("zig-signature");

const kp = try s.KeyPair.generate();
const msg = "message";
const signature = try kp.sign(msg, .{});
try s.PublicKey.verify(signature, msg, .{});

// Sizes, so a caller does not have to hardcode them
comptime {
    _ = s.seed_length;         // 32
    _ = s.signature_length;    // 64
    _ = s.public_key_length;   // 32
}
```

## API

### `SchnorrSignature(Point, Scalar)`

| Function | Description |
|---|---|
| `Sig.init(R, z)` | Build a signature from the commitment and the response |
| `sig.verify(base, public_key, msg)` | Check `z*base == R + e*public_key` |
| `Sig.challenge(base, public_key, R, msg)` | Derive the challenge with the library's hash |

### Ed25519 re-exports

| Name | Description |
|---|---|
| `Ed25519Impl` | `std.crypto.sign.Ed25519` itself |
| `KeyPair` | Key pair, with `generate()` and streaming signers |
| `PublicKey`, `SecretKey`, `Signature` | The three std types |
| `seed_length`, `signature_length`, `public_key_length` | Byte sizes |

## Running Tests

```bash
zig build test --summary all
```

## Design Notes

- The generic Schnorr has no built-in hash: it uses the hash the caller wires
  in when the signature is constructed, so the same code works over a toy group
  in the tests and over secp256k1 in production.
- `verify` returns a bool rather than an error, because "wrong signature" is an
  expected outcome and not an exceptional one.
- The secp256k1 adapters are private to the module on purpose: they exist to
  prove the generic interface is usable over a real curve, not to be an API. A
  caller with their own curve supplies their own adapter.
- Nothing in this module is constant time except Ed25519, which is the standard
  library's code. A generic Schnorr over a caller-supplied group inherits that
  group's timing behaviour.

## License

MIT or Apache-2.0
