# Security Policy

> English. [Versión en español](SECURITY.es.md)

## What this project is

`zig-zk` is a toolbox of cryptographic protocol libraries. The *verifiers* are
real implementations intended to be read and reviewed; the *provers* in this
repository are not production code.

## Supported surfaces

| Library | Status |
|---|---|
| `zig-transcript` | Reference implementation. Standard, small, reviewed. |
| `zig-curve` (via `zig-algebra`) | External dependency, out of scope here. |
| `zig-pairing` (via `zig-algebra`) | External dependency, out of scope here. |
| `zig-snark` verifier | Reference implementation. Interoperability against other Groth16 implementations is **not** yet covered by tests. |
| `zig-snark` prover | **Test oracle only.** Not constant time, blinding factors come from the caller, single scalar multiplications instead of MSMs. Do not use with secrets you care about. |
| `zig-stark` (M31, Binius) | Adopted upstream tree with two documented adaptations (`ARCHITECTURE.md`). Verify before use. |
| `zig-commitment`, `zig-signature` | Toolbox components with thin test coverage. Review before use. |

## What we consider a vulnerability

- A verifier accepting a proof that is invalid, or rejecting a valid one, for a
  statement it should handle.
- A transcript that lets two different messages produce the same transcript
  state, or a challenge that is predictable.
- A commitment scheme that leaks its blinding factor or its value.
- A signature that verifies for the wrong message, key or signer.
- Any use of a secret in a branch, a table index, or an early exit.

## What we do not consider a vulnerability

- Non-constant-time behaviour in the reference provers. It is documented as such
  in each module.
- The reference prover producing a proof for a witness that does not satisfy
  the circuit **when the prover holds the setup trapdoor**. That is inherent to
  Groth16: a prover that knows the toxic waste can prove anything. Soundness is
  a property of the setup ceremony, not of the prover code.
- Performance characteristics not documented as a guarantee.

## Reporting

Report privately to the maintainer. Include the commit, the library, a
reproducer, and whether the issue is a soundness, a correctness or a
documentation problem. We aim to acknowledge within a week.

Please do not open a public issue for an unfixed soundness problem.
