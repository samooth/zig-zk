# zig-stark

> English. [Versión en español](README.es.md)

Two complete STARK stacks, adopted from the canonical zig-stark tree: one over
M31 (a 31-bit prime) with DEEP-FRI, and one over binary fields (Binius) with
sum-check. Both are prover and verifier, not proofs of concept.

## Features

- **M31 stack** — circle FFT, three NTT variants, univariate polynomials,
  DEEP-FRI, an AIR abstraction, and four worked circuits.
- **Binius stack** — tower fields over GF(2), sum-check, four polynomial
  commitment schemes, an argument layer, and Poseidon2 recursion.
- **A checked AIR contract** — the prover is duck-typed, and `assertAir` verifies
  the contract at compile time instead of letting a malformed AIR fail somewhere
  deep inside the prover.
- **The Fiat-Shamir channel comes from `zig-transcript`**, not a vendored copy.

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
exe.root_module.addImport("zig-stark", zk.module("zig-stark"));
```

## The two stacks

**M31** (`m31/`), over the Mersenne prime 2^31 − 1, which is almost all ones in
binary and therefore unusually cheap to work with:

| Path | What is in it |
|---|---|
| `m31/field/` | M31 plus the extension tower CM31 and QM31, from zig-algebra via `m31/builtin.zig` |
| `m31/circle/` | Circle FFT geometry: points, domain, coset |
| `m31/ntt/` | `classic.zig`, `simd.zig`, `circle.zig` |
| `m31/poly/` | Univariate polynomials |
| `m31/fri.zig` | DEEP-FRI |
| `m31/air/` | The AIR contract (`contract.zig`) and the AIR types |
| `m31/stark.zig` | `GenericStark`, `StarkParams`, `BoundaryAssertion`, four worked AIRs |

**Binius** (`binius/`), over binary fields, which is a different technology
rather than a variant:

| Path | What is in it |
|---|---|
| `binius/tower.zig` | Field tower GF(2) → GF(2^128) |
| `packed_pcs.zig`, `batchpcs.zig`, `fripcs.zig` | Three polynomial commitment schemes |
| `binius/sumcheck.zig`, `binius/pcs.zig` | Consumed from `zig-algebra` at the pin, not vendored. The sum-check was confirmed byte-identical to the adopted one over value, claimed sum and six rounds; the PCS was not, and the difference was a Merkle leaf hashed twice. |
| `binius/arg.zig` | The argument layer |
| `binius/recursion/` | Poseidon2 over GF(2) |
| `binius/adder.zig`, `rangecheck.zig`, `compare.zig`, `bitpack.zig`, `pack.zig` | Constraint gadgets used by the fuzz suite |
| `tests/e2e_tests.zig` | End-to-end: prove, verify, reject a tampered witness, survive serialisation |
| `tests/fuzz.zig` | The two gadget fuzz suites, over 8 bits and over a 128-bit extension |
| `tests/field_layer.zig` | Known answers for the identities of the field layer consumed from zig-algebra |
| `tests/merkle_kat.zig` | Known answers for the Merkle commitment root, computed outside Zig |
| `tests/tower_mul.zig` | The tower's two multiplications, compared; which one runs depends on the host CPU |

`core/` holds the shared pieces: `core/hash` (Blake3 plus the `Digest` type),
merkle, `bit_utils`, SIMD helpers and serialisation.

`core/hash` and `core/merkle` are here on purpose and the reason is in
`ARCHITECTURE.md`, but they are also a fork pair against `zig-hash` and
`zig-merkle` and that has not been settled: adopting them is the same decision
the field layer was, and it waits on the same check that one took — a hash of
the files, and no signature changes. Until that runs, "kept here" is a decision
recorded, not a question closed. `core/hash` wraps `std.crypto.hash.Blake3`, so
it is correct today and is pinned with known-answer vectors; `core/merkle`
carries a GPU accelerator hook that has no counterpart upstream.

## Quick Start

This example is executed, not described: `consumer/src/main.zig` in this
repository builds it against the public API and runs it as part of
`zig build test`.

```zig
const zs = @import("zig-stark");
const m31 = zs.stark; // the M31 STARK. `zs.m31` is the field, not this.

const Stark = m31.GenericStark(m31.FibAir);
const params = m31.StarkParams{ .trace_log = 8 };

// Prover side: build a valid trace for the circuit
const trace = try m31.FibAir.generateTrace(allocator, params.traceLen());
defer m31.FibAir.freeTrace(allocator, trace);

// `claimed_fib` is the last value of column 0, not any number you like: it is
// the claim being proved.
const claimed = trace[0][params.traceLen() - 1];

// One channel per side, one label shared between them. A channel is stateful,
// so handing the same one to `prove` and then to `verify` makes the verifier
// sample a different challenge and return false -- with no error, which is the
// worst shape a failure can have in an example.
var prover_channel = zs.channel.Channel.init("mi-prueba");
var proof = try Stark.prove(allocator, params, .{ .claimed_fib = claimed }, trace, &prover_channel);
defer proof.deinit();

// Verifier side: no trace, only the proof and the public inputs
var verifier_channel = zs.channel.Channel.init("mi-prueba");
const ok = try Stark.verify(allocator, params, .{ .claimed_fib = claimed }, &proof, &verifier_channel);
```

`trace` is a list of `num_columns` column slices, each of length `traceLen()`.

If you do end up with one channel on both sides, `Channel.reset(label)` puts it
back where `init` left it and the verification succeeds; it exists for that, and
for nothing else.

## The AIR contract

`GenericStark(Air)` reads these declarations off `Air` and checks them at compile
time through `m31/air/contract.zig`. Nine are mandatory, with pinned
signatures: `num_columns`, `num_transition_constraints`, `num_boundary`,
`PublicInputs`, `evalTransition`, `maxConstraintDegree`, `boundaryAssertions`,
`generateTrace`, `freeTrace`. `generateTable` and `freeTable` become mandatory
when `num_preprocessed > 0`, and five `lookup_*` declarations when
`num_lookup_relations > 0`.

The authority for that list is the file, not this paragraph — a hand-written
table goes stale, and a table the compiler walks cannot. The full contract with
signatures is in [`m31/air/contract.zig`](m31/air/contract.zig).

`BoundaryAssertion` lives in the same file: it is the one type the prover really
needs, so it belongs next to the contract that uses it.

## Worked circuits

`FibAir` (Fibonacci, no lookups), `RangeCheckAir`, `AndTableAir` and
`MultiplicityAir` — the last three exercise the LogUp lookup path with
preprocessed tables. They double as the reference for what a real AIR looks like.

## API

| Name | Description |
|---|---|
| `m31.stark.GenericStark(Air)` | Prover and verifier for one AIR over QM31 |
| `m31.stark.StarkParams` | `trace_log`, `log_blowup`, `num_queries`, `remainder_log` |
| `m31.stark.BoundaryAssertion` | A fixed column value at a step |
| `m31.stark.FibAir` and the three LogUp AIRs | Worked circuits |
| `m31.air_contract` | The contract, its checker and `BoundaryAssertion` |
| `m31.fri`, `m31.univariate`, `m31.circle_domain` | Protocol pieces |
| `binius.stark`, `binius.sumcheck`, `binius.pcs`, `binius.arg` | Binius pieces |
| `core.hash`, `core.merkle` | Hashing and Merkle trees |
| `channel` | Re-export of `zig-transcript`'s Channel |

## Running Tests

```bash
zig build test --summary all
```

162 unit tests here, plus 16 end-to-end tests and three fuzz suites that live
in `tests/`, and three small known-answer suites in `tests/`: one guards the
identities of the field layer consumed from zig-algebra, one pins the Merkle
commitment root, which is the convention a differential found had been getting
wrong, and one compares the tower's two multiplications, which run depending on
the host CPU. The end-to-end tests do not just round-trip: they check that a
tampered committed witness is rejected, that a proof survives serialisation and
deserialisation, and that the parallel prover matches the sequential one. The
three fuzz suites: two gadget suites and one that compares the tower's two
multiplications. All three run under a leak-checking allocator, and the gadget
suites assert accept and reject on every round.

The two gadget suites differ in the field and nothing else. The quick one runs
2000 rounds over three gadgets with `Gf256` on both sides of the field pair,
chosen for speed, and a sum-check over an eight-bit field has a per-round
soundness error of order 1/|E| over the extension, and the rounds' errors add
rather than compound -- a sum bound of order k/|E| for k rounds, not a product.
`k` comes from the caller, the prover runs exactly that many rounds and the
verifier checks the count, and the count does not depend on the field: measured
over eight bits and 128 it is the same. So the field is what binds. One round
over eight bits costs 2^-8, and no choice of k makes that 2^-128, which is why
a narrow field is paid for once per round. What it stresses is the plumbing, the witness shapes
and the tamper rejection, and it says nothing about soundness. The wide one runs the same rounds over a 128-bit extension, in
far fewer of them, because a 128-bit tower product is expensive enough that
Debug avoids it elsewhere in this file.

The wide suite's claim is the narrow one, and it is the only thing it can make:
that the 128-bit path gets random witnesses. No number of rounds would make it
say that the path is sound.

## Design Notes

- The M31 field comes from zig-algebra through `m31/builtin.zig`, so there is one
  implementation of the prime rather than two. The Fiat-Shamir channel likewise
  comes from `zig-transcript`.
- `GenericStark` runs the whole protocol over QM31, the extension field, and
  commits to each trace column before sampling anything.
- Proofs are not constant time in any part that touches secret data, and the
  library does not claim otherwise.

Not adopted from upstream zig-stark, on purpose: the standalone C ABI
(`capi.zig`, `zig-capi.h`) and the CUDA kernels. If zig-stark is ever revived as
a standalone product, those live there.

## License

MIT or Apache-2.0
