# zig-snark

> English. [Versión en español](README.es.md)

Groth16 over BN254: a verification primitive and a reference prover.

**Read this first.** The verifier is the product and it is meant to be read and
reviewed. The prover is a test oracle: blinding factors come from the caller, it
is not constant time, and it uses single scalar multiplications where a real
prover would use MSMs. It exists so the verifier has something to check against,
not to be deployed.

## Features

- **Pairing check** — `e(A,B) == e(alpha,beta) * e(C,delta) * e(PV,gamma)`, four
  pairings and one exponentiation, with a 96-byte proof.
- **Untrusted input is validated** — proof elements are checked for curve and
  prime-order-subgroup membership before use, and a public-input arity that
  does not match the encodings is rejected. Neither is paranoia: `zig-pairing`
  returns the multiplicative identity for points outside the curve or the
  subgroup, so without the check a bogus element would delete a term of the
  equation instead of failing the proof.
- **Comptime-generic reference prover** — `Groth16(ic_wires, n_constraints,
  n_wires)` puts the constraint matrices on the stack and allocates nothing.
- **A prover that refuses bad witnesses** — `prove` returns
  `error.QapUnsatisfied` rather than emitting a proof for a witness that
  violates a constraint. Computing `A(tau)*B(tau) - C(tau)` unconditionally
  yields a proof that *verifies* for any statement, because the pairing
  equation then reduces to a tautology.
- **Malformed parameters are refused at compile time** — an empty
  `ic_wires`, a wire index out of range or a wire listed twice fails the build
  with a message naming the argument, in every optimisation mode.

## Installation

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.7.0.tar.gz",
        .hash = "...",
    },
},
```

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-snark", zk.module("zig-snark"));
```

## Quick Start

### Verify

```zig
const snark = @import("zig-snark");

const ok = snark.verify(
    vk.alpha_g1,     // [alpha]_1
    vk.beta_g2,      // [beta]_2
    vk.gamma_g2,     // [gamma]_2
    vk.delta_g2,     // [delta]_2
    &vk.ic,          // public-input encodings
    proof.a,
    proof.b,
    proof.c,
    &public_inputs,  // ic[1] * public_inputs[0], ic[2] * public_inputs[1], ...
);
```

`ic[0]` encodes the constant-one wire; `ic[i + 1]` encodes public input `i`. A
length mismatch returns false.

### Prove (reference only)

```zig
// 3 constraints, 5 wires, known wires {0 = the constant one, 2 = the output}
const G16 = snark.Groth16(&.{ 0, 2 }, 3, 5);

const vk = try G16.setup(&circuit, setup);           // error.DegenerateSetup
const proof = try G16.prove(&circuit, witness, setup, blind_r, blind_s);
                                                               // error.QapUnsatisfied
try std.testing.expect(G16.verifyKey(vk, proof, .{output}));
```

## API

### Free functions

| Function | Description |
|---|---|
| `verify(a1, b2, g2, d2, ic, pa, pb, pc, pub_in)` | The pairing check; false on any mismatch |
| `Groth16(ic_wires, n_constraints, n_wires)` | Reference prover for a fixed-size R1CS |

### Types re-exported from zig-algebra

`Fr`, `G1`, `G2`, `Fp12T`, `g1_gen`, `g2_gen`. They are re-exported so a caller
does not have to import two packages for one signature.

### Inside `Groth16(...)`

These types are not `pub`, so a caller infers them (`const vk = try
G16.setup(...)`) instead of naming them.

| Name | Description |
|---|---|
| `Circuit` | `a`, `b`, `c` constraint matrices, row-major |
| `Setup` | `tau`, `alpha`, `beta`, `gamma`, `delta`; `isValid()` rejects a degenerate setup |
| `VerifyingKey` | `alpha_g1`, `beta_g2`, `gamma_g2`, `delta_g2`, `ic` |
| `Proof` | `a: G1`, `b: G2`, `c: G1` |
| `setup(circuit, setup)` | Precompute the public-input encodings |
| `prove(circuit, witness, setup, blind_r, blind_s)` | Produce a proof |
| `verifyKey(vk, proof, public_inputs)` | The same check, with types |
| `satisfies(circuit, witness)` | Whether the witness meets every constraint |
| `Error` | `DegenerateSetup`, `QapUnsatisfied` |

## Running Tests

```bash
zig build test --summary all
```

The suite is assertion-based, and the negative cases carry as much weight as the
roundtrip: wrong public inputs, each proof element tampered with, off-curve
elements, a mismatched setup, blinding factors including zero, malformed arity,
an unsatisfied witness, a degenerate setup, and pairing bilinearity checked
against `powFast` — because if the pairing were not bilinear, the rest would be
decoration.

Interoperability is covered in the direction that matters for a verifier.
`src/vectors/` holds a verification key, a proof and a public signal produced by
**snarkjs 0.7.6** on BN254, and the suite verifies that proof with `verify`. The
vectors are `@embedFile`d rather than read at runtime so the test cannot depend
on a working directory, and the parsers divide by the projective `z` instead of
assuming it is one, because an assumption that happens to hold on the committed
file is exactly what breaks on someone else's proof.

`src/vectors/regenerate.mjs` is the recipe. It is not a byte-for-byte
reproducer: `powersoftau new` draws fresh randomness, so a regenerated zkey, and
therefore `vk.json` and `proof.json`, differ from the committed ones. What a
re-run guarantees is the shape, which is the part that matters -- it is why the
test's parser cannot have been fitted to one lucky file.

The reverse direction -- this repository's prover producing a proof that snarkjs
accepts -- has been checked once and holds, including the convention that `ic[0]`
is the point at infinity. It is **not** enforced by `zig build test`, because it
would make a Node runtime a test dependency; treat it as a recorded result, not
a ratchet.

## Design Notes

The QAP conventions this prover depends on — the per-pair Lagrange denominator,
`A(tau)` as the interpolant of the per-constraint row evaluations,
`t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, the private-wire-only sum in `c`, the
meaning of `ic[0]`, and the algebraic condition the pairing verifies — are
written down once in [ARCHITECTURE.md](../../ARCHITECTURE.md) with the
consequence of breaking each one.

Scalar multiplication uses zig-algebra's windowed Jacobian ladder, not a local
implementation.

## License

MIT or Apache-2.0
