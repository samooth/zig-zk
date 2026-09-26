# Documentación de arquitectura de zig-zk

> Español. [English version](architecture.md)

## Visión general

`zig-zk` es un monorepositorio de librerías de protocolos criptográficos
construido sobre [`zig-algebra`](https://github.com/samooth/zig-algebra).
zig-algebra aporta las matemáticas; zig-zk aporta los protocolos que las
consumen.

Todo lo que sigue describe el código tal como existe. Lo que no aparece en la
API de una librería no existe, y lo que aparece como *no implementado* es una
idea pendiente, no una promesa.

## Arquitectura

```
Externo: zig-algebra v0.3.2 (primitivas matemáticas, sin lógica de protocolos)
    │
Capa 1: transcript          (Fiat-Shamir: absorb/squeeze, Channel duck-typed)
    │
Capa 2: commitment          (argumento de producto interno, Pedersen, Shamir, Σ)
    │
Capa 3: signature, air      (Schnorr + Ed25519, marco AIR genérico)
    │
Capa 4: stark, snark        (sistemas de prueba completos: STARK M31/Binius, Groth16)
```

La única dependencia dentro del repositorio es `stark -> transcript`: el árbol de
STARK consume el `Channel` de `zig-transcript` en lugar de llevar su propia copia.

## Grafo de módulos

Exactamente como está cableado en `build.zig`:

| Módulo | Fuente raíz | Deps de zig-algebra | Deps internas de zig-zk |
|---|---|---|---|
| `zig-transcript` | `libs/transcript/src/root.zig` | algebra-traits, hash, rng | — |
| `zig-commitment` | `libs/commitment/src/root.zig` | algebra-traits, field, merkle, poly | — |
| `zig-air` | `libs/air/src/root.zig` | algebra-traits | — |
| `zig-signature` | `libs/signature/src/root.zig` | algebra-traits, curve, hash, rng | — |
| `zig-snark` | `libs/snark/src/root.zig` | field, curve, pairing | — |
| `zig-stark` | `libs/stark/root.zig` | field | transcript |

## 1. transcript (capa 1)

Transcripciones Fiat-Shamir sobre Blake3. Tres tipos con propósitos distintos:

**`Transcript`** — absorb/squeeze con contador.

- `init(label)`, `absorb(bytes)`, `absorbField(F, x)`, `absorbFieldSlice(F, xs)`
- `squeeze(out)`, `squeezeField(F)` (muestreo por rechazo, uniforme sobre `F`),
  `squeezeU64()`, `squeezeU256()`
- `clone()` bifurca el estado; `reset(label)` reinicia el separador de dominio
- Cada absorción lleva prefijo de longitud; cada squeeze incrementa un contador
  interno, así que dos squeezes seguidos nunca devuelven los mismos bytes.

**`LabelledTranscript`** — cada operación lleva una etiqueta explícita, de modo
que confundir dos protocolos exige una colisión de resumen y no un prefijo
compartido.

**`Channel`** — duck-typed, la forma que espera `libs/stark`.

- `absorb(value)` y `absorbMany(...)` aceptan cualquier cosa con `SIZE`,
  `toBytes` y `fromBytes` (no hace falta el trait de campo)
- `absorbDigest(digest)` es el puente hacia el tipo `Digest` interno del árbol de
  STARK
- `sample(T)`, `sampleIndex(n)`, `sampleBytes(out)`

## 2. commitment (capa 2)

**`Ipa(F)`** — argumento de producto interno sobre cualquier campo de
zig-algebra.

- `init(allocator, n, seed)`, `deinit()`
- `commit(a, b, c) -> F`, `innerProduct(a, b) -> F`
- `prove(allocator, a, b) -> Proof`, `verify(C, *Proof) -> bool`
- Los desafíos salen de una **esponja Fiat-Shamir en marcha** (Blake3): todo
  valor absorbido avanza el estado, así que el desafío de la ronda *k* ata el
  enunciado completo y todas las rondas anteriores.

**Pedersen** — `Pedersen(Point)`: `commit`, `verify`, `add`, `sub`, genérico
sobre cualquier tipo de punto con las operaciones necesarias.

**Shamir** — `Share(Scalar)`, `split`, `reconstruct`, `lagrangeCoefficient`, y
un campo de prueba módulo 7 usado por las pruebas.

**Protocolos Σ** — `SchnorrPoK(Point, Scalar)` como prueba de conocimiento, y
`CdsOrProof(Point, Scalar)`, la prueba OR de uno entre muchos de CDS '94.

**`MerkleTree`** — reexportación de `zig-merkle`.

Aquí no están: KZG, FRI, DARK ni Ligero. KZG y FRI viven en `zig-algebra` para
el árbol de STARK, y ninguno de los dos se reexporta como API de esquema de
compromiso.

## 3. signature (capa 3)

**`SchnorrSignature(Point, Scalar)`** — genérico sobre cualquier par
Point/Scalar con `add`, `scalarMul`, `eql` (y `Scalar` con `fromBytes`, `zero`,
`add`, `mul`). `init(R, z)`, `verify(base, public_key, msg)`,
`challenge(...)`.

**`Ed25519Impl`** — un alias delgado sobre `std.crypto.sign.Ed25519`
(determinista, de tiempo constante, sin código nuestro en el camino crítico),
junto con sus tipos `KeyPair`/`PublicKey`/`SecretKey`/`Signature` para las API
de streaming.

**Adaptadores de secp256k1** — `libs/signature/src/root.zig` adapta los puntos y
escalares de `std.crypto.ecc.Secp256k1` a la interfaz genérica de Schnorr
(`toBytes`/`fromBytes`/`scalarMul`/`eql`).

No están: ECDSA, BLS, MuSig2.

## 4. air (capa 3)

Representación algebraica intermedia genérica, parametrizada por campo y por
tipo de entradas públicas: `Air(BaseField, PublicInputs)`, más
`BoundaryConstraint`, `TransitionConstraint`, `EvaluationFrame` (par de filas
actual/siguiente) y `ExecutionTrace` (matriz de traza con asignador, con
`get`/`set`/`getRow`/`getCol`).

El contrato que un AIR debe cumplir para servir a `GenericStark` está escrito en
[ARCHITECTURE.md](../ARCHITECTURE.es.md).

## 5. stark (capa 4)

El árbol canónico de zig-stark, adoptado tal cual. Véase `ARCHITECTURE.es.md`
para las dos adaptaciones permanentes (el canal vive en `zig-transcript`;
M31/CM31/QM31 vienen de zig-algebra mediante `m31/builtin.zig`).

**Pila M31** — `m31/`: FFT circular (`circle/`), NTT (`ntt/classic.zig`,
`ntt/simd.zig`, `ntt/circle.zig`), polinomios univariantes (`poly/`), DEEP-FRI
(`fri.zig`) y `stark.zig` con `GenericStark(Air)` más AIRs ya resueltos
(`FibAir`, `RangeCheckAir`, `AndTableAir`, `MultiplicityAir`).

**Pila Binius** — `binius/`: campos en torre, sum-check, variantes de PCS
(`pcs`, `packed_pcs`, `batchpcs`, `fripcs`, `addfri`), capa de argumentos
(`arg`), `recursion/` (Poseidon2 sobre GF(2)) y los gadgets de restricciones que
usa la suite de fuzz (`adder`, `rangecheck`, `compare`, `bitpack`, `pack`).

**core** — `core/hash` (Blake3 + `Digest`), `core/merkle`, `bit_utils`, ayudas
SIMD, serialización.

## 6. snark (capa 4)

Groth16 sobre BN254: una primitiva de verificación más un prover de referencia
usado como oráculo de pruebas, y no como generador de pruebas de producción (véase
*Postura de seguridad*).

### Verificación

```zig
pub fn verify(
    a1: G1,          // [alpha]_1
    b2: G2,          // [beta]_2
    g2: G2,          // [gamma]_2
    d2: G2,          // [delta]_2
    ic: []const G1,  // codificaciones de las entradas públicas
    pa: G1, pb: G2, pc: G1,   // la prueba
    pub_in: []const Fr,
) bool
```

Comprueba `e(A, B) == e(alpha, beta) * e(C, delta) * e(PV, gamma)`, es decir
`e(-A, B) * e(alpha, beta) * e(C, delta) * e(PV, gamma) == 1`.

`ic[0]` codifica el **hilo constante uno**; `ic[i + 1]` codifica la entrada
pública `i`, cuyo valor llega en `pub_in`. Un desajuste de longitudes significa
una prueba malformada y devuelve `false`.

Los elementos de la prueba se validan contra curva y subgrupo de orden primo
antes de usarse. Esto no es paranoia matemática: el `pairing()` de `zig-pairing`
devuelve la identidad multiplicativa para puntos fuera de la curva o del
subgrupo de orden r, así que sin la comprobación un elemento falso **elimina un
término** de la ecuación en lugar de hacer fallar la prueba.

### Prover de referencia

```zig
const G16 = Groth16(&.{ 0, 2 }, 3, 5);   // hilos conocidos, restricciones, hilos
const vk = try G16.setup(&circuit, setup);
const proof = try G16.prove(&circuit, witness, setup, blind_r, blind_s);
try G16.verifyKey(vk, proof, .{output});
```

`Groth16(ic_wires, n_constraints, n_wires)` está parametrizado en comptime, así
que las matrices de restricciones viven en la pila y nada asigna memoria
—salvo los valores `Proof`/`VerifyingKey` que devuelve el llamante—. `ic_wires[0]`
debe ser el hilo constante uno; el resto son las entradas públicas en orden.
Todos los demás hilos son privados y solo aparecen dentro del elemento `c` de la
prueba.

Errores: `error.DegenerateSetup` (residuo tóxico a cero, `gamma == delta`, o un
trapdoor dentro del dominio de evaluación) y `error.QapUnsatisfied`.

### Convenciones

Las convenciones del QAP de las que depende este prover —el denominador de
Lagrange por par, `A(tau)` como interpolante de las evaluaciones por
restricción, `t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, la suma de `c` solo sobre
hilos privados y el significado de `ic[0]`— están escritas una sola vez, con la
consecuencia de romper cada una, en
[ARCHITECTURE.md](../ARCHITECTURE.es.md).

## Gestión de dependencias

`build.zig.zon` fija zig-algebra como un tarball publicado:

```zig
.zig_algebra = .{
    .url = "https://github.com/samooth/zig-algebra/archive/refs/tags/v0.3.2.tar.gz",
    .hash = "zig_algebra-0.3.2-PdVS05JfEwAc7M57KrjFSdjN2X4pIR6AxllIPzW6N85Q",
},
```

Quien consume la dependencia obtiene los mismos módulos:

```zig
const algebra = b.dependency("zig_algebra", .{});
const field = algebra.module("zig-field");
const curve = algebra.module("zig-curve");
const pairing = algebra.module("zig-pairing");
```

### Actualizar zig-algebra

`scalarMul` sobre puntos de Weierstrass afinos y proyectivos es una escalera por
ventanas de 4 bits en coordenadas jacobianas (~8x más rápido, O(1)
inversiones). Llámala en lugar de escribir tu propia escalera: una
implementación local es redundante y un riesgo de fallo. `zig-snark` usa
`p.scalarMul(s)` en todo el código.

Para regenerar la huella, apunta `.url` al tag nuevo y ejecuta `zig build`: el
error de discrepancia imprime la huella correcta.

## Postura de seguridad

- **Tiempo constante donde importa**: Ed25519 (`std.crypto.sign`), Blake3 y la
  aritmética de campo en Montgomery de zig-algebra.
- **Sin tiempo constante, por diseño y por documentación**: `curve.scalarMul`
  ramifica según los bits del escalar; el prover de referencia de Groth16 toma
  los factores de cegado del llamante y usa multiplicaciones por escalar
  individuales donde un prover de verdad usaría sumas de múltiplos. Ninguno de
  los dos se usa con datos secretos. `libs/snark` lo dice en el comentario de
  su módulo.
- **Fiat-Shamir**: todos los tipos de transcripción separan dominios y atan el
  estado absorbido hacia adelante. La esponja en marcha del argumento de
  producto interno es lo que hace que la secuencia de desafíos no sea maleable.
- **Higiene de la configuración**: `Setup.isValid` de Groth16 rechaza
  `gamma == delta`, que
  colapsaría el separador público/privado, y un trapdoor dentro de `H`, que haría
  `t(tau)` nulo.

## Versionado

SemVer, con la convención habitual de `0.x` que también usa zig-algebra: en
`0.y.z`, el MINOR lleva los cambios incompatibles y el PATCH solo cambios
aditivos y correcciones.

| Cambio | Versión |
|---|---|
| Corregir un fallo, añadir una prueba, documentación, o un `build` que no estaba cableado | PATCH |
| Añadir una función, un tipo, o un módulo entero | PATCH (aditivo) |
| Cambiar o quitar una firma pública, mover un tipo entre módulos, o un cambio de comportamiento del que un consumidor pueda depender | MINOR |
| Todo aquello que obligue a un consumidor a editar algo para seguir compilando | MINOR |

No hay `1.0.0` a la vista, así que el MINOR es el canal de cambios incompatibles;
la línea PATCH se mantiene aburrida a propósito.

La versión del manifiesto y el tag de git se fijan en el mismo commit de
publicación, y el tag apunta a ese commit. Un commit de publicación contiene: el
incremento en `build.zig.zon`, la sección del `CHANGELOG.md`, y nada más. Los
commits y los tags van firmados con GPG.

## Idiomas de la documentación

Cada fichero markdown existe en inglés y en español. El nombre sin sufijo es el
inglés (así GitHub lo sirve por defecto) y su pareja en español lleva el sufijo
`.es.md`; cada fichero enlaza a su pareja en sus dos primeras líneas.
`zig build check-docs`, del que también depende `zig build test`, comprueba que
las parejas existen, que cada fichero declara su idioma, que la prosa no se ha
colado de un idioma en otro y que los ficheros en español evitan los anglicismos
que tienen equivalente limpio en español. Los bloques de código y los
identificadores quedan exentos, porque son iguales en ambos.

## Pruebas

```bash
zig build test --summary all                    # todas las suites, Debug
zig build test -Doptimize=ReleaseFast           # lo mismo, ~20x más rápido para snark
```

El `build.zig` raíz es el canónico: cablea los seis módulos más las suites e2e y
de fuzz de stark, y trae zig-algebra desde el tarball pinneado, así que funciona
desde un clon limpio. Los `build.zig` por librería existen para el trabajo
aislado y resuelven zig-algebra desde el mismo tarball pinneado.

El paso `test` de la raíz compila y ejecuta todas las suites: 271 pruebas
repartidas en transcript (14), commitment (11), air (5), signature (6), stark
(208), snark (11), más las suites e2e (16) y de fuzz de stark.
`libs/stark/tests/fuzz.zig` es un `main` que entra en pánico si detecta fugas y
afirma que acepta y que rechaza en cada vuelta, así que su resultado lo
sostienen las aserciones y no el resumen que imprime.

La CI ejecuta la suite en Debug sobre Linux, macOS y Windows mediante
`.github/actions/setup-zig`, que descarga el compilador desde ziglang.org
(resolviendo `master` a través de `download/index.json`).

## Cómo contribuir

1. Las librerías de protocolos van en `libs/<nombre>/` con un `build.zig` que
   exponga un módulo.
2. Toda dependencia nueva de álgebra se declara en `build.zig` y en
   `build.zig.zon`; mantén sincronizadas las dos tablas de módulos de este
   documento.
3. Las pruebas afirman, nunca imprimen. Un `std.debug.print` en una prueba es un
   fallo: no reporta nada al arnés y puede imprimir `true` junto a una aserción
   que falla.
4. Prefiere un error devuelto a un `std.debug.assert` para todo lo que un
   llamante pueda alcanzar a través de la API: las aserciones desaparecen en
   ReleaseFast.
5. Ejecuta `zig fmt` y la suite completa antes de abrir un PR.
6. Cada fichero markdown necesita su pareja en el otro idioma, y
   `zig build check-docs` lo verifica.
