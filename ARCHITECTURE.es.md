# Arquitectura de zig-zk

> Español. [English version](ARCHITECTURE.md)

## Estratificación del repositorio

```
zig-algebra      primitivas matemáticas (sin protocolos)
   ↑ dependencia por tarball pinneado
zig-zk           protocolos zk: AIR · STARK · compromisos · firmas · snark
```

- **zig-algebra**: campos (M31, CM31, QM31, BN254, BLS12-381, Pasta, binarios),
  curvas, emparejamientos óptimos, sumas de múltiplos (Pippenger), KZG, resúmenes
  criptográficos, merkle, NTT, polinomios, transcripción Fiat-Shamir, FRI primitivo, álgebra
  lineal, serialización.
  Regla: aquí no entra lógica de protocolos.
- **zig-zk**: consume algebra como dependencia externa y aloja los protocolos.
  `libs/stark` aloja el árbol canónico adoptado de zig-stark@HEAD
  (M31 DEEP-FRI + Binius), con dos adaptaciones permanentes:
  1. El canal de Fiat-Shamir vive en `libs/transcript` (un port duck-typed del
     canal original; `absorbDigest(anytype)`).
  2. M31, CM31 y QM31 vienen de los campos de zig-algebra mediante
     `m31/builtin.zig` (la antigua dependencia por URL a samooth/zig-field está
     retirada).

## Decisiones sobre duplicados (auditoría posterior a la adopción)

| Componente | Decisión | Motivo |
|---|---|---|
| Canal | **zig-transcript** (único) | Ya está portado y validado; stark lo consume como módulo |
| `core/hash` (Blake3 + `Digest`) | Se queda en stark | El tipo Digest está fuertemente acoplado al merkle y al FRI internos de stark |
| core/merkle | Se queda en stark | Es genérico sobre Digest; el merkle de algebra es byte a byte |
| FRI | DEEP-FRI/circle en stark (producción); algebra/fri queda como primitiva educativa | Requisitos distintos; no forzar unificación |
| m31/cm31/qm31 como producto | **Eliminados** | Sustituidos por los campos de zig-algebra mediante builtin.zig |
| Multiplicación por escalar de curvas | **Siempre la de zig-algebra** (`p.scalarMul(s)`) | Es una escalera por ventanas en coordenadas jacobianas: O(1) inversiones, y cualquier implementación local es un riesgo de fallo |
| El contrato del AIR | **Dentro de `zig-stark`**, en `m31/air/contract.zig` | Lo comprueba el compilador, así que no puede quedarse viejo; un módulo suelto con un solo consumidor sería generalidad especulativa |

## El contrato del AIR

El prover funciona por convención: nunca instancia un «tipo de framework AIR»,
sino que lee un conjunto de declaraciones del propio tipo del AIR. Ese contrato
vivía solo como accesos dispersos dentro de `stark.zig`, y nadie comprobaba la
parte obligatoria: olvidar una declaración producía un error desde dentro del
prover que nunca mencionaba lo que faltaba.

Ahora vive en un solo sitio,
[`libs/stark/m31/air/contract.zig`](../libs/stark/m31/air/contract.zig), y
`assertAir(Air, F)` lo comprueba en tiempo de compilación desde `GenericStark`.
La autoridad de la lista es ese fichero, no este párrafo, y ese es justo el
punto: una tabla escrita a mano se queda vieja; una tabla que el compilador
recorre no puede.

**Obligatorios** (nueve): `num_columns`, `num_transition_constraints`,
`num_boundary`, `PublicInputs`, `evalTransition`, `maxConstraintDegree`,
`boundaryAssertions`, `generateTrace`, `freeTrace`. No solo se comprueba que
existan, sino sus firmas.

**Condicionados a `num_preprocessed > 0`** (dos): `generateTable`, `freeTable`.

**Condicionados a `num_lookup_relations > 0`** (cinco): `num_lookup_columns`,
`lookup_selector_columns`, `lookup_key_columns`, `lookup_table_columns`,
`lookup_multiplicity_columns`.

**Opcionales, si faltan valen cero** (tres): `num_preprocessed`,
`num_lookup_columns`, `num_lookup_relations`.

`BoundaryAssertion` vive en el mismo fichero: es el único tipo que el prover
necesita de verdad, así que pertenece al contrato que lo usa.

Existía un módulo `zig-air` para esto. Duplicaba el mismo código, nada de él se
consumía, y sus cinco constructores no los instanciaba nadie. Se eliminó en
0.3.0 en lugar de fusionarlo, porque un módulo con un solo consumidor es
generalidad especulativa. Si algún día aparece un segundo motor de STARK, la
extracción es mecánica.

## `libs/snark`: convenciones del prover de Groth16

`Groth16(ic_wires, n_constraints, n_wires)` es genérico por comptime sobre un
R1CS. `verify` es la primitiva que debe consumir el resto del ecosistema; el
prover es un oráculo de pruebas, no un prover de producción.

El dominio es `H = {1, ..., n_constraints}`. `L_g(tau)` es la base de Lagrange de
`H` en el trapdoor, con el denominador **por par** `(H_g, H_j)` dentro del
producto doble. Sacar un `tau - H_j` compartido fuera del producto produce
evaluaciones erróneas de forma silenciosa.

Convenciones que no son evidentes:

| Convención | Regla | Qué se rompe si se ignora |
|---|---|---|
| Polinomios del QAP | `A(tau) = sum_g (A . z)(g) * L_g(tau)`: el interpolante en `tau` de las **evaluaciones por restricción**, no un polinomio en el índice del hilo | `h` no existe, `C` es incorrecto |
| El cociente | `t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, y solo vale si el testigo satisface el R1CS | el prover produce pruebas que **verifican** para cualquier enunciado falso (la ecuación de emparejamiento degenera en una tautología) → `prove` devuelve `error.QapUnsatisfied` |
| La suma de `c` | solo hilos privados (los que no están en `ic_wires`) | doble conteo, o perder un hilo privado |
| `ic[0]` | el encoding propio del hilo constante uno, `(beta*A_0 + alpha*B_0 + C_0)(tau)/gamma`, **no** un `[1]_1` literal | aparece un término `gamma` que ya no se cancela |
| `Setup` | `gamma != delta`, ningún valor a cero, `tau` fuera de `H` | configuración degenerada → `error.DegenerateSetup` |

`verify` comprueba la pertenencia a la curva y al subgrupo de orden primo de
`A`, `B` y `C` antes de usarlos. No es paranoia matemática: `zig-pairing`
devuelve la identidad multiplicativa para los puntos que están fuera de la curva
o del subgrupo, así que sin la comprobación un elemento falso **borra un
término** de la ecuación en lugar de hacer fallar la prueba.

La condición algebraica que verifica el emparejamiento, útil para auditar
cualquier cambio en la fórmula de `C`:

```
Y = alpha * B(tau) + beta * A(tau) + A(tau)*B(tau) - gamma * PV
```

donde `Y` es el numerador que el prover mete en `c` y `PV` es lo que el
verificador recompone a partir de `ic`. La fórmula de `C` está construida para
que esa igualdad se cumpla.

## Convenciones de tooling

- **Los tipos genéricos** se declaran con un `return struct { ... };` explícito.
  La forma con cuerpo implícito no es válida en cuanto el tipo expone más de una
  función.
- **Las pruebas** afirman, nunca imprimen. Un `std.debug.print` dentro de una
  prueba no reporta nada al arnés y puede imprimir `true` junto a una aserción
  que falla.
- **Errores antes que aserciones**: `std.debug.assert` desaparece en ReleaseFast.
  Todo lo alcanzable desde la API pública devuelve un error explícito.
- **El build raíz es la única entrada**: el `build.zig` de la raíz compila y
  ejecuta todas las suites; los `build.zig` por librería existen para el trabajo
  aislado y resuelven zig-algebra desde el mismo tarball pinneado.

## Piezas de zig-stark NO adoptadas de forma deliberada (producto congelado)

- `capi.zig` y `zig-capi.h`: la ABI en C del producto independiente.
- `cuda/*`: kernels para GPU (trabajo en marcha aguas arriba).

Si zig-stark llegara a resucitar como producto independiente, esas piezas viven
ahí; zig-zk no las necesita.
