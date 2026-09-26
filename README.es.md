# zig-zk

> Español. [English version](README.md)

![CI](https://github.com/samooth/zig-zk/actions/workflows/ci.yml/badge.svg)

Un ecosistema de protocolos criptográficos y pruebas de conocimiento cero para
Zig, construido sobre `zig-algebra`.

Requiere Zig 0.16 y `zig-algebra` **v0.3.2** (fijado por huella en
`build.zig.zon`).

## Documentación

Cada documento existe en inglés y en español; el nombre sin sufijo es el inglés y
la pareja en español añade `.es`.

| Documento | Contenido |
|---|---|
| [docs/architecture.es.md](docs/architecture.es.md) | API por librería, grafo de módulos, política de dependencias y versionado, postura de seguridad, pruebas |
| [ARCHITECTURE.es.md](ARCHITECTURE.es.md) | Estratificación del repositorio, decisiones de unificación, contrato del AIR, convenciones del prover de Groth16 |
| [CHANGELOG.es.md](CHANGELOG.es.md) | Historial de publicaciones |
| [SECURITY.es.md](SECURITY.es.md) | Qué está auditado, qué no, y qué cuenta como vulnerabilidad |
| [AGENTS.es.md](AGENTS.es.md) | Reglas de trabajo para agentes |

## Visión

`zig-zk` es un **ecosistema de librerías de protocolos** que consume la
infraestructura algebraica de `zig-algebra` para implementar STARKs, SNARKs,
firmas digitales y esquemas de compromiso.

Cada librería:
- Es **usable por separado** (con sus dependencias declaradas)
- Usa **comptime** para monomorfización (sin coste)
- **No asigna memoria** siempre que puede
- Depende de `zig-algebra` como paquete externo

## Relación con zig-algebra

```
+------------------+     +------------------+
|    zig-algebra   | --> |      zig-zk      |
| (infraestructura)|     |   (protocolos)   |
|                  |     |                  |
| - algebra-traits |     | - transcript     |
| - field          |     | - commitment     |
| - curve          |     | - signature      |
| - poly           |     | - air            |
| - ntt            |     | - stark          |
| - merkle         |     | - snark          |
| - pairing        |     |                  |
| - linalg         |     |                  |
+------------------+     +------------------+
```

`zig-algebra` aporta las matemáticas. `zig-zk` aporta los protocolos que usan
esas matemáticas.

## Capas

```
Capa 0  +-----------------------------------------+
        |  zig-algebra (dependencia externa)      |
        |  - field, curve, poly, ntt, merkle      |
        |  - pairing, linalg, hash, rng           |
        +-----------------------------------------+
                   |
Capa 1  +----------+----------+
        |    transcript       |
        |  (Fiat-Shamir)      |
        +----------+----------+
                   |
Capa 2  +----------+----------+
        |    commitment       |
        |  (IPA, Pedersen,    |
        |   Shamir, Sigma)    |
        +----------+----------+
                   |
Capa 3  +----------+----------+----------+
        |   signature  |   air   |  stark  |
        |  (Schnorr,  | (modelo | (M31,    |
        |   Ed25519)  |   AIR)  |  Binius) |
        +--------------+---------+---------+
                   |
Capa 4  +----------+----------+
        |    snark           |
        |  (Groth16 sobre    |
        |     BN254)         |
        +----------+----------+
```

## Librerías

| Librería | Descripción | Deps de zig-algebra |
|---|---|---|
| [transcript](libs/transcript/) | Transcripciones Fiat-Shamir (absorb-squeeze, separación de dominios, desafíos, Channel) | algebra-traits, hash, rng |
| [commitment](libs/commitment/) | Esquemas de compromiso (IPA, Pedersen, Shamir, Sigma) | algebra-traits, field, merkle, poly |
| [signature](libs/signature/) | Firmas digitales (Schnorr genérico, Ed25519, adaptadores de secp256k1) | algebra-traits, curve, hash, rng |
| [air](libs/air/) | Modelo de datos del AIR para backends de STARK | algebra-traits |
| [stark](libs/stark/) | Prover/verificador de STARK (pilas M31 DEEP-FRI + Binius) | field |
| [snark](libs/snark/) | zkSNARKs (verificador de Groth16 + prover de referencia sobre BN254) | field, curve, pairing |

Las dos tablas se mantienen sincronizadas con `build.zig`. Las dos listas de
dependencias solo difieren en la fila de `stark`: esa es la única dependencia
interna del repositorio, porque stark consume `zig-transcript` y el `field` de
zig-algebra directamente.

## Tabla de dependencias

| Librería | Deps de zig-algebra | Deps internas de zig-zk |
|---|---|---|
| transcript | algebra-traits, hash, rng | — |
| commitment | algebra-traits, field, merkle, poly | — |
| signature | algebra-traits, curve, hash, rng | — |
| air | algebra-traits | — |
| stark | field | transcript |
| snark | field, curve, pairing | — |

## Instalación

```zig
// build.zig.zon — dependencia por ruta (desarrollo local)
.{
    .dependencies = .{
        .zig_zk = .{
            .path = "../zig-zk",
        },
    },
}
```

```zig
// build.zig
const zk = b.dependency("zig_zk", .{
    .target = target,
    .optimize = optimize,
});

// Cada librería se expone como su propio módulo:
const transcript_mod = zk.module("zig-transcript");
const commitment_mod = zk.module("zig-commitment");
const signature_mod = zk.module("zig-signature");
const air_mod = zk.module("zig-air");
const stark_mod = zk.module("zig-stark");
const snark_mod = zk.module("zig-snark");
```

## Primeros pasos

```zig
const std = @import("std");
const transcript = @import("zig-transcript");

// Transcripción Fiat-Shamir (sobre Blake3, absorb/squeeze)
var t = transcript.Transcript.init("mi-protocolo-v1");
t.absorb(&bytes_publicos);
t.absorbField(F, compromiso);
const desafio = t.squeezeField(F);
```

```zig
const std = @import("std");
const signature = @import("zig-signature");

// Las firmas de Schnorr son genéricas sobre cualquier par Point/Scalar con:
//   Point: add, scalarMul, eql   Scalar: fromBytes, zero, add, mul
// Ejemplo con un campo/grupo de juguete; para los adaptadores de secp256k1
// sobre std.crypto.ecc, mira libs/signature/src/root.zig.
const Sig = signature.SchnorrSignature(TestPoint, F7);

// Firmar: R = k*G, e = H(G, P, R, msg), z = k + e*x
const sig = Sig.init(R, z);

// Verificar: z*G == R + e*P
try std.testing.expect(sig.verify(G, P, "mensaje"));
```

```zig
const std = @import("std");
const commitment = @import("zig-commitment");
const zf = @import("zig-field");

// Argumento de producto interno sobre cualquier campo de zig-algebra
var seed: [32]u8 = undefined;
std.mem.writeInt(u64, seed[0..8], 42, .little);
var ipa = try commitment.Ipa(zf.M31).init(allocator, 8, seed);
defer ipa.deinit();

const c = commitment.Ipa(zf.M31).innerProduct(a, b);
const C = ipa.commit(a, b, c);
const proof = try ipa.prove(allocator, a, b);
defer proof.deinit(allocator);
try ipa.verify(C, &proof);
```

```zig
const std = @import("std");
const snark = @import("zig-snark");

// Verificación Groth16 sobre BN254: e(-A,B)*e(alpha1,beta2)*e(C,delta2)*e(PV,gamma2)==1
const ok = snark.verify(a1, b2, gamma_g2, delta_g2, &ic, pi_a, pi_b, pi_c, &entradas_publicas);
```

```zig
const std = @import("std");
const snark = @import("zig-snark");

// Prover de referencia para un R1CS de tamaño fijado en compilación:
// 3 restricciones, 5 hilos, hilos conocidos {0 = el uno constante, 2 = la
// salida pública}.
const G16 = snark.Groth16(&.{ 0, 2 }, 3, 5);

const vk = try G16.setup(&circuito, setup);
const proof = try G16.prove(&circuito, testigo, setup, blind_r, blind_s); // error.QapUnsatisfied
try std.testing.expect(G16.verifyKey(vk, proof, .{salida}));
```

## Ejecutar las pruebas

El build raíz es el canónico: cablea todos los módulos y ejecuta todas las
suites, y resuelve `zig-algebra` desde el tarball pinneado, así que funciona
desde un clon limpio.

```bash
# Probar todas las librerías (compila Y ejecuta todas las suites)
zig build test --summary all

# Lo mismo, optimizado: la suite de snark, llena de emparejamientos,
# pasa de ~57s a ~1s
zig build test -Doptimize=ReleaseFast --summary all
```

Cada librería lleva además su propio `build.zig` para el trabajo aislado,
resolviendo `zig-algebra` desde el mismo tarball pinneado:

```bash
cd libs/transcript && zig build test --summary all
```

Las pruebas afirman, nunca imprimen: un `std.debug.print` dentro de una prueba no
reporta nada al arnés y puede imprimir `true` junto a una aserción que falla.

## Principios de diseño

1. **Corrección primero**: toda la criptografía está verificada matemáticamente
2. **Sin dependencias externas**: solo la biblioteca estándar de Zig + zig-algebra
3. **Comptime primero**: todas las constantes se calculan en compilación
4. **Sin asignaciones**: solo pila cuando es posible
5. **Genérico**: los algoritmos funcionan sobre cualquier campo o curva mediante
   parámetros de comptime

## Licencia

MIT o Apache-2.0
