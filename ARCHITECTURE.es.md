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
| Modelo de datos del AIR | **zig-air, fuente única** (`libs/air`) | Véase «El contrato del AIR» más abajo |

## El contrato del AIR

`libs/air` y `libs/stark/m31/air/*` contenían el mismo código por duplicado, y
ninguna de las dos copias se consumía: el prover de STARK no instancia
`Air(BaseField, PublicInputs)`. Lo que `GenericStark` lee de verdad es un
conjunto de miembros, por convención, sobre el tipo del AIR:

| Miembro | Clase | Significado |
|---|---|---|
| `num_columns`, `num_transition_constraints`, `num_boundary` | `comptime usize` | Forma de la traza y del conjunto de restricciones |
| `PublicInputs` | cualquier tipo | Lo que el verificador recibe |
| `maxConstraintDegree(n)` | función | Cota superior del grado de las restricciones, que fija el grado de composición |
| `evalTransition(x, current, next, out)` | función | Rellena las evaluaciones de las restricciones para un par de filas |
| `boundaryAssertions(public, n, out)` | función | Valores fijos de columnas en pasos dados |
| `generateTrace(allocator, n)` | función | Construye una traza válida (lado del prover) |
| `num_preprocessed`, `num_lookup_columns`, `num_lookup_relations` | opcionales | Tablas LogUp y preprocesadas; si faltan, es que no hay |

`BoundaryAssertion` es el único de esos tipos que el prover usa de verdad, así
que es el que corresponde a este módulo. Cualquier otra cosa que viva aquí es
documentación: si aparece una segunda implementación de STARK, este contrato es lo que
tiene que cumplir, y conviene comprobarlo en tiempo de compilación en lugar de
descubrirlo con un fallo dentro del prover.

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
