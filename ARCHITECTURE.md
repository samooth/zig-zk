# Arquitectura zig-zk

## Estratificación de repos

```
zig-algebra      primitivas matemáticas (sin protocolos)
   ↑ dependencia por tarball pinneado (v0.3.2)
zig-zk           protocolos zk: AIR · STARK · commitments · firmas · snark
```

- **zig-algebra**: campos (M31, CM31, QM31, BN254, BLS12-381, Pasta, binarios),
  curvas, pairings óptimos, MSM (Pippenger), KZG, hash, merkle, NTT, poly,
  transcript/Fiat-Shamir, FRI primitivo, linalg, serialization.
  Regla: nada de lógica de protocolos aquí.
- **zig-zk**: consume algebra como dependencia externa y aloja los protocolos.
  `libs/stark` aloja el árbol canónico adoptado de zig-stark@HEAD
  (M31 DEEP-FRI + Binius), con dos adaptaciones permanentes:
  1. Fiat-Shamir Channel vive en `libs/transcript` (port duck-typed del
     channel original; `absorbDigest(anytype)`).
  2. M31/CM31/QM31 vienen de `zig-algebra` field vía `m31/builtin.zig`
     (el antiguo dep por URL a samooth/zig-field está retirado).

## Decisiones sobre duplicados (auditoría post-adopción)

| Componente | Decisión | Motivo |
|---|---|---|
| Channel | **zig-transcript** (único) | Ya portado y validado; stark lo consume como módulo |
| core/hash (Blake3+Digest) | Se queda en stark | Tipo Digest fuertemente acoplado a merkle/FRI internos |
| core/merkle | Se queda en stark | Genérico sobre Digest; el merkle de algebra es byte-based |
| FRI | DEEP-FRI/circle en stark (producción); algebra/fri queda como primitiva educativa | Requisitos distintos; no forzar dedupe |
| m31/cm31/qm31 vendidos | **Eliminados** | Sustituidos por zig-algebra fields vía builtin.zig |
| Scalar multiplication de curvas | **siempre la de zig-algebra** (`p.scalarMul(s)`) | ladder windowed en Jacobiano: O(1) inversiones y cero implementaciones locales que mantener |

## Piezas de zig-stark NO adoptadas (producto congelado)

- `capi.zig` + `zig-capi.h`: ABI C del producto standalone.
- `cuda/*`: kernels GPU (WIP upstream).
Si alguna vez se reactúa zig-stark como producto, estos viven ahí;
zig-zk no los necesita.

## `libs/snark`: convenciones del prover Groth16

`Groth16(ic_wires, n_constraints, n_wires)` es genérico por comptime sobre un
R1CS. `verify` es la primitiva que debe consumir el resto del ecosistema; el
prover es un oráculo de tests, no un prover de producción.

Dominio `H = {1, ..., n_constraints}`; `L_g(tau)` es la base de Lagrange de `H`
en el trapdoor, con denominador **por par** `(H_g - H_j)` dentro del producto
doble. Compartir una normalización `tau - H_j` fuera del producto da
evaluaciones erróneas de forma silenciosa.

Convenciones no evidentes:

| Convención | Regla | Consecuencia si se viola |
|---|---|---|
| Polinomios QAP | `A(tau) = sum_g (A . z)(g) * L_g(tau)`: interpolante en `tau` de las **evaluaciones por restricción**, no polinomio en el índice del wire | `h` inexistente, `C` incorrecto |
| Cuciente | `t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, y solo vale si el witness satisface el R1CS | el prover produce proofs que **verifican** para cualquier statement falso (la ecuación de pairing degenera en tautología) → `prove` devuelve `error.QapUnsatisfied` |
| Suma de `c` | solo wires **privados** (los que no están en `ic_wires`) | doble conteo o wire privado perdido |
| `ic[0]` | es el encoding propio del wire constante uno, `(beta*A_0 + alpha*B_0 + C_0)(tau)/gamma` — **no** un `[1]_1` literal | aparece un término `gamma` que ya no se cancela |
| Setup | `gamma != delta`, sin valores cero, `tau` fuera de `H` | setup degenerado → `error.DegenerateSetup` |

`verify` valida pertenencia a curva y subgrupo de orden primo de `A`, `B`, `C`
antes de usarlos. No es paranoia matemática: `zig-pairing` devuelve la
identidad multiplicativa para puntos fuera de curva/subgrupo, así que sin la
comprobación un elemento falso **borra un término** de la ecuación en lugar de
rechazar el proof.

Detalle algebraico de la condición que verifica el pairing, útil para auditar
cualquier cambio en la fórmula de `C`:

```
Y = alpha * B(tau) + beta * A(tau) + A(tau)*B(tau) - gamma * PV
```

donde `Y` es el numerador que el prover mete en `c` y `PV` el valor que el
verificador recompone desde `ic`. La fórmula de `C` está construida para que
esa igualdad se cumpla.

## Convenciones de tooling

- **Tipos genéricos**: se declaran con `return struct { ... };` explícito. La
  forma con cuerpo implícito no es válida cuando el tipo genérico expone más de
  una función.
- **Tests**: assert, nunca print. Un `std.debug.print` dentro de un test no
  reporta nada al harness y puede imprimir `true` junto a un assert que falla.
- **Errores sobre asserts**: `std.debug.assert` desaparece en ReleaseFast. Todo
  lo alcanzable desde la API pública devuelve error explícito.
- **Build raíz como entrada única**: el `build.zig` de la raíz es el que compila
  y ejecuta todas las suites; los `build.zig` por librería existen para trabajo
  standalone.
