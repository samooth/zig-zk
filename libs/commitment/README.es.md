# zig-commitment

> Español. [English version](README.md)

Esquemas de compromiso para pruebas de conocimiento cero: el argumento de
producto interno, compromisos de Pedersen, reparto de secretos de Shamir y dos
protocolos Σ.

## Características

- **IPA (argumento de producto interno)** — una prueba de tamaño logarítmico al
  estilo Bulletproofs de que `⟨a, b⟩ = c`, con los desafíos atados por una esponja
  Fiat-Shamir en marcha
- **Compromisos de Pedersen** — `commit(v, r) = v·G + r·H`, homomorfos bajo la
  suma, genéricos sobre cualquier tipo de punto
- **Reparto de secretos de Shamir** — divide un secreto en participaciones y
  reconstruye con interpolación de Lagrange, genérico sobre el tipo escalar.
  `split` recibe el `std.Random` de quien llama, y los coeficientes por encima del
  secreto se sacan de él
- **Protocolos Σ** — `SchnorrPoK` (prueba de conocimiento) y `CdsOrProof` (la
  prueba OR de uno entre muchos de CDS '94)
- **Genérico** — todo está parametrizado por el tipo de campo o de punto
- **`MerkleTree`** — reexportación de `zig-merkle`

El prover y el verificador reciben un asignador explícito: el argumento guarda la
transcripción de desafíos y los vectores plegados, así que esta librería reserva
memoria por diseño y lo libera todo en `deinit`.

## Instalación

Añade esto a tu `build.zig.zon`:

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.7.0.tar.gz",
        .hash = "...",
    },
},
```

Y luego en tu `build.zig`:

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-commitment", zk.module("zig-commitment"));
```

## Primeros pasos

### IPA (argumento de producto interno)

`n` es el número de elementos y **debe ser una potencia de dos**; `init` devuelve
`error.LengthNotPowerOfTwo` en caso contrario. La verificación necesita el
compromiso, no solo el producto interno: el valor `⟨a, b⟩` por sí solo no fija un
par de vectores comprometidos único.

```zig
const zc = @import("zig-commitment");
const zf = @import("zig-field");

// 8 elementos, generadores derivados de la semilla
var seed: [32]u8 = undefined;
std.mem.writeInt(u64, seed[0..8], 42, .little);
var ipa = try zc.Ipa(zf.M31).init(allocator, 8, seed);
defer ipa.deinit();

const c = try zc.Ipa(zf.M31).innerProduct(a, b);
const C = try ipa.commit(a, b, c);

const proof = try ipa.prove(allocator, a, b);
defer proof.deinit(allocator);
try ipa.verify(C, &proof);   // devuelve error si no cuadra
```

### Compromisos de Pedersen

```zig
const P = zc.Pedersen(MyPoint, MyScalar);

const commitment = P.commit(value, blinding, G, H);
try std.testing.expect(P.verify(commitment, value, blinding, G, H));

// Homomórfico: commit(a) + commit(b) = commit(a + b)
const sum = commitment_a.add(commitment_b);
const diff = commitment_a.sub(commitment_b);
```

### Reparto de secretos de Shamir

```zig
const S = zc.shamir.Share(MyScalar);

const participaciones = try zc.shamir.split(MyScalar, secreto, umbral, total, allocator, rnd);
const reconstruido = try zc.shamir.reconstruct(MyScalar, participaciones);
```

## API

### `Ipa(F)`

| Función | Descripción |
|---|---|
| `Ipa(F).init(allocator, n, seed)` | Crea el argumento; `n` elementos, potencia de dos |
| `Ipa(F).innerProduct(a, b)` | Calcula `⟨a, b⟩`, `error.LengthMismatch` |
| `ipa.commit(a, b, c)` | Compromete al par con el producto interno `c`, `error.LengthMismatch` |
| `ipa.prove(allocator, a, b)` | Produce la prueba |
| `ipa.verify(compromiso, *prueba)` | Verifica contra el compromiso; devuelve error si falla |
| `prueba.deinit(allocator)` | Libera la prueba |
| `ipa.deinit()` | Libera los generadores |

### `Pedersen(Point)`

| Función | Descripción |
|---|---|
| `P.commit(valor, ceguado, G, H)` | `valor·G + ceguado·H` |
| `P.verify(C, valor, ceguado, G, H)` | Comprueba una apertura |
| `P.add(C1, C2)` | Suma homomórfica |
| `P.sub(C1, C2)` | Resta homomórfica |

### `shamir`

| Función | Descripción |
|---|---|
| `shamir.Share(Scalar)` | El tipo de participación |
| `shamir.split(Scalar, secreto, umbral, total, allocator, rnd)` | Divide en `total` participaciones, `error.InvalidThreshold` o `error.TooFewShares`. Recibe el `std.Random` de quien llama y no puede tener uno por defecto: una fuente fija haría públicos los coeficientes no secretos del polinomio |
| `shamir.reconstruct(Scalar, participaciones)` | Reconstruye con `umbral` o más, `error.NoShares` |
| `shamir.lagrangeCoefficient(...)` | Coeficiente de interpolación |

### Protocolos Sigma

| Función | Descripción |
|---|---|
| `SchnorrPoK(Point, Scalar).prove(...)` | Prueba de conocimiento de Schnorr |
| `CdsOrProof(Point, Scalar).create(...)` | Prueba OR de uno entre muchos de CDS '94 |
| `CdsOrProof(Point, Scalar).verify(...)` | Verifica una prueba OR |

## Ejecutar las pruebas

```bash
zig build test --summary all
```

## Notas de diseño

- Los desafíos del IPA salen de una **esponja** Blake3 *en marcha*: absorbe los
  generadores, `n` y el compromiso antes de la primera ronda, y la respuesta de
  cada ronda después. Derivar los desafíos de un estado estático dejaría el
  argumento maleable.
- Los valores absorbidos llevan prefijo de longitud, así que dos transcripciones
  distintas no se pueden alcanzar partiendo o concatenando las entradas de otra
  manera.
- La verificación reproduce la esponja en lugar de recalcular nada a partir de la
  prueba, así que una prueba no se puede reutilizar bajo un enunciado distinto.
- Los compromisos de Pedersen son perfectamente ocultos y vinculantes
  computacionalmente, dado el supuesto del logaritmo discreto sobre los
  generadores.

## Licencia

MIT o Apache-2.0
