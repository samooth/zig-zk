# zig-stark

> Español. [English version](README.md)

Dos pilas completas de STARK, adoptadas del árbol canónico de zig-stark: una
sobre M31 (un primo de 31 bits) con DEEP-FRI, y otra sobre campos binarios
(Binius) con suma-producto. Las dos son prover y verificador, no pruebas de
concepto.

## Características

- **Pila M31** — FFT circular, tres variantes de NTT, polinomios univariantes,
  DEEP-FRI, una abstracción de AIR y cuatro circuitos ya resueltos.
- **Pila Binius** — campos en torre sobre GF(2), suma-producto, cuatro esquemas
  de compromiso polinómico, una capa de argumentos y recursión con Poseidon2.
- **Un contrato de AIR comprobado** — el prover funciona por convención, y
  `assertAir` verifica el contrato en tiempo de compilación en vez de dejar que
  un AIR mal formado falle en algún punto profundo del prover.
- **El canal de Fiat-Shamir viene de `zig-transcript`**, no de una copia propia.

## Instalación

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
exe.root_module.addImport("zig-stark", zk.module("zig-stark"));
```

## Las dos pilas

**M31** (`m31/`), sobre el primo de Mersenne 2³¹ − 1, que en binario es casi
todo unos y por eso resulta inusualmente barato de trabajar:

| Ruta | Qué contiene |
|---|---|
| `m31/field/` | M31 más la torre de extensiones CM31 y QM31, desde zig-algebra mediante `m31/builtin.zig` |
| `m31/circle/` | Geometría de la FFT circular: puntos, dominio, coset |
| `m31/ntt/` | `classic.zig`, `simd.zig`, `circle.zig` |
| `m31/poly/` | Polinomios univariantes |
| `m31/fri.zig` | DEEP-FRI |
| `m31/air/` | El contrato del AIR (`contract.zig`) y los tipos del AIR |
| `m31/stark.zig` | `GenericStark`, `StarkParams`, `BoundaryAssertion` y cuatro AIR resueltos |

**Binius** (`binius/`), sobre campos binarios, que es otra tecnología y no una
variante:

| Ruta | Qué contiene |
|---|---|
| `binius/tower.zig` | Torre de campos GF(2) → GF(2¹²⁸), consumida del `zig-algebra` del pin, no vendorizada |
| `packed_pcs.zig`, `batchpcs.zig`, `fripcs.zig` | Tres esquemas de compromiso polinómico |
| `binius/sumcheck.zig`, `binius/pcs.zig` | Se consumen de `zig-algebra` en la versión fijada, no están en el árbol. El suma-producto resultó idéntico byte a byte al adoptado en el valor, la suma declarada y seis rondas; la PCS no, y la diferencia era una hoja del Merkle hasheada dos veces. |
| `binius/arg.zig` | La capa de argumentos |
| `binius/recursion/` | Poseidon2 sobre GF(2) |
| `binius/adder.zig`, `rangecheck.zig`, `compare.zig`, `bitpack.zig`, `pack.zig` | Gadgets de restricciones que usa la suite de fuzz |
| `tests/e2e_tests.zig` | De extremo a extremo: probar, verificar, rechazar un testigo manipulado, sobrevivir a la serialización |
| `tests/fuzz.zig` | Las dos suites de fuzz de gadgets, sobre 8 bits y sobre una extensión de 128 bits |
| `tests/field_layer.zig` | Respuestas conocidas para las identidades de la capa de campo consumida de zig-algebra |
| `tests/merkle_kat.zig` | Respuestas conocidas para la raíz del compromiso del Merkle, calculadas fuera de Zig |
| `tests/tower_mul.zig` | Las dos multiplicaciones de la torre, comparadas; cuál corre depende de la CPU del anfitrión |

`core/` contiene las piezas compartidas: `core/hash` (Blake3 más el tipo
`Digest`), `core/merkle`, `bit_utils`, ayudas SIMD y serialización.

`core/hash` y `core/merkle` están aquí a propósito y la razón está en
`ARCHITECTURE.md`, pero también son un par fork frente a `zig-hash` y
`zig-merkle`, y eso no está resuelto: adoptarlos es la misma decisión que fue la
de la capa de campo, y espera la misma comprobación que aquella — un hash de los
ficheros, y ningún cambio de firma. Hasta que corra, "aquí se quedan" es una
decisión registrada, no una pregunta cerrada. `core/hash` envuelve
`std.crypto.hash.Blake3`, así que hoy es correcto y está fijado con vectores de
respuesta conocida; `core/merkle` lleva un hook de acelerador de GPU que no
tiene contraparte aguas arriba.

## Primeros pasos

Este ejemplo se ejecuta, no se describe: `consumer/src/main.zig` en este
repositorio lo compila contra la API pública y lo ejecuta como parte de
`zig build test`.

```zig
const zs = @import("zig-stark");
const m31 = zs.stark; // el STARK sobre M31. `zs.m31` es el campo, no esto.

const Stark = m31.GenericStark(m31.FibAir);
const params = m31.StarkParams{ .trace_log = 8 };

// Lado del prover: construir una traza válida para el circuito
const traza = try m31.FibAir.generateTrace(allocator, params.traceLen());
defer m31.FibAir.freeTrace(allocator, traza);

// `claimed_fib` es el último valor de la columna 0, no cualquier número: es la
// afirmación que se demuestra.
const reclamado = traza[0][params.traceLen() - 1];

// Un canal por lado, una etiqueta compartida. Un canal tiene estado, así que
// pasarle el mismo a `prove` y luego a `verify` hace que el verificador
// amostra un reto distinto y devuelva false, sin ningún error, que es la peor
// forma que puede tener un fallo en un ejemplo.
var canal_del_prover = zs.channel.Channel.init("mi-prueba");
var prueba = try Stark.prove(allocator, params, .{ .claimed_fib = reclamado }, traza, &canal_del_prover);
defer prueba.deinit();

// Lado del verificador: sin traza, solo la prueba y las entradas públicas
var canal_del_verificador = zs.channel.Channel.init("mi-prueba");
const ok = try Stark.verify(allocator, params, .{ .claimed_fib = reclamado }, &prueba, &canal_del_verificador);
```

Si aun así acabas con un solo canal en los dos lados, `Channel.reset(etiqueta)`
lo devuelve al estado en que lo dejó `init` y la verificación tiene éxito; existe
para eso y para nada más.

`traza` es una lista de `num_columns` fragmentos de columna, cada uno de longitud
`traceLen()`.

## El contrato del AIR

`GenericStark(Air)` lee estas declaraciones del AIR y las comprueba en tiempo de
compilación mediante `m31/air/contract.zig`. Nueve son obligatorias, con sus
firmas fijadas: `num_columns`, `num_transition_constraints`, `num_boundary`,
`PublicInputs`, `evalTransition`, `maxConstraintDegree`, `boundaryAssertions`,
`generateTrace` y `freeTrace`. `generateTable` y `freeTable` pasan a ser
obligatorias cuando `num_preprocessed > 0`, y cinco declaraciones `lookup_*`
cuando `num_lookup_relations > 0`.

La autoridad de esa lista es el fichero, no este párrafo: una tabla escrita a
mano se queda vieja, y una tabla que el compilador recorre no puede. El
contrato completo con las firmas está en
[`m31/air/contract.zig`](m31/air/contract.zig).

`BoundaryAssertion` vive en ese mismo fichero: es el único tipo que el prover
necesita de verdad, así que pertenece junto al contrato que lo usa.

## Circuitos resueltos

`FibAir` (Fibonacci, sin consultas), `RangeCheckAir`, `AndTableAir` y
`MultiplicityAir` — los tres últimos ejercitan la vía de consultas LogUp con
tablas preprocesadas. Sirven además de referencia de cómo es un AIR de verdad.

## API

| Nombre | Descripción |
|---|---|
| `m31.stark.GenericStark(Air)` | Prover y verificador para un AIR sobre QM31 |
| `m31.stark.StarkParams` | `trace_log`, `log_blowup`, `num_queries`, `remainder_log` |
| `m31.stark.BoundaryAssertion` | Un valor fijo de columna en un paso |
| `m31.stark.FibAir` y los tres AIR con LogUp | Circuitos resueltos |
| `m31.air_contract` | El contrato, su comprobación y `BoundaryAssertion` |
| `m31.fri`, `m31.univariate`, `m31.circle_domain` | Piezas del protocolo |
| `binius.stark`, `binius.sumcheck`, `binius.pcs`, `binius.arg` | Piezas de Binius |
| `core.hash`, `core.merkle` | Resumen y árboles de Merkle |
| `channel` | Reexportación del `Channel` de `zig-transcript` |

## Ejecutar las pruebas

```bash
zig build test --summary all
```

162 pruebas unitarias aquí, más 16 de extremo a extremo y tres suites de fuzz
que viven en `tests/`, y tres suites pequeñas de respuesta conocida en `tests/`:
una vigila las identidades de la capa de campo consumida de zig-algebra, una
fija la raíz del compromiso del Merkle, que era la convención que un diferencial
descubrió que se estaba equivocando, y una compara las dos multiplicaciones de
la torre, que dependen de la CPU del anfitrión. Las pruebas de extremo a extremo no se limitan al ciclo
completo: comprueban que un testigo comprometido y manipulado se rechaza, que
una prueba sobrevive a serializar y deserializar, y que el prover paralelo da el
mismo resultado que el secuencial. Las tres suites de fuzz son dos de gadgets y
una que compara las dos multiplicaciones de la torre. Las tres corren bajo un
asignador que detecta fugas, y las de gadgets afirman que aceptan y que rechazan
en cada vuelta.

Las dos suites de gadgets se diferencian en el campo y en nada más. La rápida da
2000 vueltas sobre tres gadgets con `Gf256` en los dos lados del par de campos,
elegido por velocidad, y el error de solidez de una ronda de suma-producto sobre
un campo de ocho bits es del orden de 1/|E| sobre la extensión, y los errores
de las rondas se suman en vez de multiplicarse: una cota de suma del orden
k/|E| para k rondas, no un producto. `k` lo proporciona quien llama, el prover
hace exactamente esas rondas, el verificador comprueba la cuenta, y la cuenta no
depende del campo: medido sobre ocho bits y sobre 128 es el mismo. Así que el
que ata es el campo. Una ronda sobre ocho bits cuesta 2^-8, y ninguna elección de
k lo convierte en 2^-128, que es la razón por la que un campo estrecho se paga
una vez por ronda. Lo que
presiona es la fontanería, las formas de testigo y el rechazo de una
manipulación. No dice nada sobre solidez. La ancha da las mismas vueltas
sobre una extensión de 128 bits, con muchas menos, porque un producto en una
torre de 128 bits es lo bastante caro como para que Debug lo evite en otros
puntos de este fichero.

La afirmación de la suite ancha es la estrecha, y es lo único que puede hacer:
que el camino de 128 recibe testigos aleatorios. Ningún número de vueltas
haría que dijera que el camino es sound.

## Lo que no hace la ruta por defecto

Los seis constructores de conveniencia de `binius/arg.zig` seleccionan
`CommittedMlePcsUnsafe`, y `binius/stark.zig` y `binius/arg.zig` llevan ambos
`SumcheckUnsafe(E)` fijo. Del par de campos nunca se entera, así que un par de menos
de 128 bits se rechaza en vez de probarse sobre él. Ese indicador,
`allow_small_field`, todavía no llega a ninguna de las dos capas, así que la
afirmación honesta es que hoy no se puede elegir el valor por defecto seguro y el que
sale es el barato. Es el primer punto abierto de [TODO.es.md](../../TODO.es.md), y
que sea el primero es porque está medido: 128 bits cuesta 5,0× por ronda frente a la
configuración de 8 bits, lineal en toda la suite de fuzz. Si el valor por defecto se
mueve es una decisión de producto.

## Notas de diseño

- El campo M31 viene de zig-algebra mediante `m31/builtin.zig`, así que hay una
  sola implementación del primo en vez de dos. El canal de Fiat-Shamir viene
  igual de `zig-transcript`.
- `GenericStark` ejecuta todo el protocolo sobre QM31, el campo de extensión, y
  compromete cada columna de la traza antes de muestrear nada.
- Las pruebas no son de tiempo constante en ninguna parte que toque datos
  secretos, y la librería no afirma lo contrario.

No se han adoptado de zig-stark aguas arriba, a propósito: la ABI en C del
producto independiente (`capi.zig`, `zig-capi.h`) y los kernels de CUDA. Si
algún día zig-stark resucita como producto independiente, esas piezas viven ahí.

## Licencia

MIT o Apache-2.0
