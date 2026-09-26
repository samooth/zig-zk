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
| AIR data model | **zig-air, single source** (`libs/air`) | See "The AIR contract" below |

## The AIR contract

`libs/air` and `libs/stark/m31/air/*` used to hold the same code twice, and
neither copy was consumed: the STARK prover does not instantiate
`Air(BaseField, PublicInputs)`. What `GenericStark` actually reads is a
duck-typed set of members on the AIR type:

| Member | Kind | Meaning |
|---|---|---|
| `num_columns`, `num_transition_constraints`, `num_boundary` | `comptime usize` | Shape of the trace and the constraint set |
| `PublicInputs` | any type | What the verifier is told |
| `maxConstraintDegree(n)` | function | Upper bound on the constraint degree, which drives the composition degree |
| `evalTransition(x, current, next, out)` | function | Fill the constraint evaluations for one row pair |
| `boundaryAssertions(public, n, out)` | function | Fixed column values at given steps |
| `generateTrace(allocator, n)` | function | Build a valid trace (prover side) |
| `num_preprocessed`, `num_lookup_columns`, `num_lookup_relations` | optional | LogUp and preprocessed tables; absent means "none" |

`BoundaryAssertion` is the only one of those types that the prover really uses,
so it is the one that belongs in this module. Anything else here is
documentation: if a second STARK backend appears, this contract is what it must
satisfy, and it should be checked at compile time rather than discovered from a
crash inside the prover.

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
