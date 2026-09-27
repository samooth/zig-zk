# zig-zk Architecture

> English. [Versión en español](ARCHITECTURE.es.md)

## Repository layering

```
zig-algebra      mathematical primitives (no protocols)
   ↑ pinned tarball dependency
zig-zk           zk protocols: AIR · STARK · commitments · signatures · snark
```

- **zig-algebra**: fields (M31, CM31, QM31, BN254, BLS12-381, Pasta, binary),
  curves, optimal pairings, MSMs (Pippenger), KZG, hash, merkle, NTT, poly,
  transcript/Fiat-Shamir, primitive FRI, linalg, serialisation.
  Rule: no protocol logic in here.
- **zig-zk**: consumes algebra as an external dependency and hosts the
  protocols. `libs/stark` hosts the canonical tree adopted from zig-stark@HEAD
  (M31 DEEP-FRI + Binius), with two permanent adaptations:
  1. The Fiat-Shamir channel lives in `libs/transcript` (a duck-typed port of
     the original channel; `absorbDigest(anytype)`).
  2. M31/CM31/QM31 come from zig-algebra's field via `m31/builtin.zig` (the
     old URL dependency on samooth/zig-field is retired).

## Duplicate decisions (post-adoption audit)

| Component | Decision | Reason |
|---|---|---|
| Channel | **zig-transcript** (only one) | Already ported and validated; stark consumes it as a module |
| core/hash (Blake3 + Digest) | Stays in stark | The Digest type is tightly coupled to stark's internal merkle/FRI |
| core/merkle | Stays in stark | Generic over Digest; algebra's merkle is byte-based |
| FRI | DEEP-FRI/circle in stark (production); algebra/fri remains an educational primitive | Different requirements; do not force a dedupe |
| m31/cm31/qm31 as sold | **Removed** | Replaced by zig-algebra's fields via builtin.zig |
| Curve scalar multiplication | **Always zig-algebra's** (`p.scalarMul(s)`) | It is a windowed ladder in Jacobian coordinates: O(1) inversions, and any local implementation is a bug risk |
| The AIR contract | **In `zig-stark`**, at `m31/air/contract.zig` | It is checked by the compiler, so it cannot go stale; a standalone module with one consumer would be speculative |

## The AIR contract

The prover is duck-typed: it never instantiates an "AIR framework" type, it
reads a set of declarations off the AIR type itself. That contract used to live
only as scattered accesses inside `stark.zig`, and nothing checked the mandatory
part — forgetting a declaration produced an error from deep inside the prover
that never mentioned what was missing.

It now lives in one place, [`libs/stark/m31/air/contract.zig`](../libs/stark/m31/air/contract.zig),
and `assertAir(Air, F)` checks it at compile time from `GenericStark`. The
authority for the list is that file, not this paragraph, which is the whole
point: a hand-written table goes stale, a table the compiler walks cannot.

**Mandatory** (nine): `num_columns`, `num_transition_constraints`,
`num_boundary`, `PublicInputs`, `evalTransition`, `maxConstraintDegree`,
`boundaryAssertions`, `generateTrace`, `freeTrace`. Their signatures are pinned,
not just their presence.

**Conditional on `num_preprocessed > 0`** (two): `generateTable`, `freeTable`.

**Conditional on `num_lookup_relations > 0`** (five): `num_lookup_columns`,
`lookup_selector_columns`, `lookup_key_columns`, `lookup_table_columns`,
`lookup_multiplicity_columns`.

**Optional, absent means zero** (three): `num_preprocessed`,
`num_lookup_columns`, `num_lookup_relations`.

`BoundaryAssertion` lives in the same file: it is the one type the prover really
needs, so it belongs with the contract that uses it.

There was a standalone `zig-air` module for this. It duplicated the same code,
none of it was consumed, and its five constructors were instantiated by nobody.
It was removed in 0.3.0 rather than fused, because a module with a single
consumer is speculative generality. If a second STARK backend ever appears, the
extraction is mechanical.

## `libs/snark`: Groth16 prover conventions

`Groth16(ic_wires, n_constraints, n_wires)` is comptime-generic over an R1CS.
`verify` is the primitive the rest of the ecosystem should call; the prover is a
test oracle, not a production prover.

The domain is `H = {1, ..., n_constraints}`. `L_g(tau)` is the Lagrange basis
of `H` at the trapdoor, with the denominator **per pair** `(H_g, H_j)` inside
the double product. Hoisting a shared `tau - H_j` out of the product yields
wrong evaluations silently.

Conventions that are not obvious:

| Convention | Rule | What breaks if you ignore it |
|---|---|---|
| QAP polynomials | `A(tau) = sum_g (A . z)(g) * L_g(tau)`: the interpolant at `tau` of the **per-constraint row evaluations**, not a polynomial in the wire index | `h` does not exist, `C` is wrong |
| The quotient | `t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, and it only holds if the witness satisfies the R1CS | the prover emits proofs that **verify** for any false statement (the pairing equation degenerates into a tautology) → `prove` returns `error.QapUnsatisfied` |
| The `c` sum | private wires only (those not in `ic_wires`) | double counting, or a lost private wire |
| `ic[0]` | the constant-one wire's own `(beta*A_0 + alpha*B_0 + C_0)(tau)/gamma` encoding — **not** a literal `[1]_1` | a `gamma` term appears that no longer cancels |
| `Setup` | `gamma != delta`, no zeroed values, `tau` outside `H` | degenerate setup → `error.DegenerateSetup` |

`verify` checks curve and prime-order-subgroup membership of `A`, `B` and `C`
before using them. That is not mathematical paranoia: `zig-pairing` returns the
multiplicative identity for points that are off the curve or outside the
subgroup, so without the check a bogus element **deletes a term** of the equation
instead of failing the proof.

The algebraic condition the pairing verifies, useful for auditing any change to
the formula for `C`:

```
Y = alpha * B(tau) + beta * A(tau) + A(tau)*B(tau) - gamma * PV
```

where `Y` is the numerator the prover puts into `c` and `PV` is what the
verifier recomposes from `ic`. The formula for `C` is built so that this
equality holds.

## Tooling conventions

- **Generic types** are declared with an explicit `return struct { ... };`. The
  implicit-body form is not valid once the type exposes more than one function.
- **Tests** assert, they never print. A `std.debug.print` in a test reports
  nothing to the harness and can print `true` next to a failing assertion.
- **Errors over asserts**: `std.debug.assert` disappears in ReleaseFast.
  Everything reachable from the public API returns an explicit error.
- **The root build is the single entry point**: the root `build.zig` compiles
  and runs every suite; the per-library `build.zig` files exist for standalone
  work and resolve zig-algebra from the same pinned tarball.

## zig-stark pieces deliberately NOT adopted (frozen product)

- `capi.zig` + `zig-capi.h`: the C ABI of the standalone product.
- `cuda/*`: GPU kernels (upstream work in progress).

If zig-stark is ever revived as a standalone product, those live there; zig-zk
does not need them.
