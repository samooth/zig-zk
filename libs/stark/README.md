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
| `binius/sumcheck.zig` | The sum-check protocol |
| `binius/pcs.zig`, `packed_pcs.zig`, `batchpcs.zig`, `fripcs.zig` | Four polynomial commitment schemes |
| `binius/arg.zig` | The argument layer |
| `binius/recursion/` | Poseidon2 over GF(2) |
| `binius/adder.zig`, `rangecheck.zig`, `compare.zig`, `bitpack.zig`, `pack.zig` | Constraint gadgets used by the fuzz suite |

`core/` holds the shared pieces: `core/hash` (Blake3 plus the `Digest` type),
`core/merkle`, `bit_utils`, SIMD helpers and serialisation.

## Quick Start

```zig
const zs = @import("zig-stark");
const m31 = zs.m31.stark;

// The AIR is a type; the prover is generic over it
const Stark = m31.GenericStark(m31.FibAir);

const params = m31.StarkParams{ .trace_log = 8 };
var channel = zs.channel.Channel.init("mi-prueba");

// Prover side: build a valid trace for the circuit
const trace = try m31.FibAir.generateTrace(allocator, params.traceLen());
defer m31.FibAir.freeTrace(allocator, trace);

const proof = try Stark.prove(allocator, params, .{ .claimed_fib = ... }, trace, &channel);
defer proof.deinit();

// Verifier side: no trace, only the proof and the public inputs
const ok = try Stark.verify(allocator, params, .{ .claimed_fib = ... }, &proof, &channel);
```

`trace` is a list of `num_columns` column slices, each of length `traceLen()`.

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

208 unit tests here, plus 16 end-to-end tests and a fuzz suite that lives in
`tests/`. The end-to-end tests do not just round-trip: they check that a
tampered committed witness is rejected, that a proof survives serialisation and
deserialisation, and that the parallel prover matches the sequential one. The
fuzz suite runs 2000 iterations over three gadgets and asserts accept and reject
on every round, with a leak-checking allocator.

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
