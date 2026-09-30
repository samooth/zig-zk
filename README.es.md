# zig-zk

> Español. [English version](README.md)

![CI](https://github.com/samooth/zig-zk/actions/workflows/ci.yml/badge.svg)

Un ecosistema de protocolos criptográficos y pruebas de conocimiento cero para
Zig, construido sobre `zig-algebra`.

Requiere Zig 0.16 y `zig-algebra` **v0.6.0** (fijado por huella en
`build.zig.zon`). El pin es lo que la compilación resuelve de verdad, así que esta
línea es una afirmación sobre él, y `zig build check-contract` falla cuando las dos
se contradicen.

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
| [TODO.es.md](TODO.es.md) | Trabajo abierto, ordenado por lo que cierra más casos de uso |

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
| zig-algebra      |     | zig-zk           |
| (infraestructura)| --> | (protocolos)     |
|                  |     |                  |
| - algebra-traits |     | - transcript     |
| - field          |     | - commitment     |
| - curve          |     | - signature      |
| - binary-field   |     | - stark          |
| - poly           |     | - snark          |
| - ntt            |     |                  |
| - fri            |     |                  |
| - kzg            |     |                  |
| - merkle         |     |                  |
| - hash           |     |                  |
| - pairing        |     |                  |
| - linalg         |     |                  |
| - bigint         |     |                  |
| - parallel       |     |                  |
| - rng            |     |                  |
| - serialization  |     |                  |
| - transcript     |     |                  |
+------------------+     +------------------+
```

`zig-algebra` aporta las matemáticas. `zig-zk` aporta los protocolos que usan
esas matemáticas.

La columna de la izquierda es el directorio de módulos del tarball fijado, los 17.
Es el pin lo que convierte eso en un hecho y no en un recuerdo, y
`zig build check-contract` falla cuando este fichero y el pin discrepan sobre la
versión.

## Capas

```
Capa 0  +-----------------------------------------+
        |  zig-algebra (dependencia externa)      |
        |  - field, curve, binary-field, poly     |
        |  - ntt, fri, kzg, merkle, hash         |
        |  - pairing, linalg, bigint, parallel   |
        |  - rng, serialization, algebra-traits  |
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

| Librería | Descripción | Referencia |
|---|---|---|
| [transcript](libs/transcript/) | Transcripciones Fiat-Shamir (absorb-squeeze, separación de dominios, desafíos, Channel) | [README](libs/transcript/README.es.md) |
| [commitment](libs/commitment/) | Esquemas de compromiso (IPA, Pedersen, Shamir, Sigma) | [README](libs/commitment/README.es.md) |
| [signature](libs/signature/) | Firmas digitales (Schnorr genérico, Ed25519, adaptadores de secp256k1) | [README](libs/signature/README.es.md) |
| [stark](libs/stark/) | Prover/verificador de STARK (pilas M31 DEEP-FRI + Binius) | [README](libs/stark/README.es.md) |
| [snark](libs/snark/) | zkSNARKs (verificador de Groth16 + prover de referencia sobre BN254) | [README](libs/snark/README.es.md) |

Las dependencias por librería no se repiten aquí: el grafo de módulos, las capas
y la política de versionado viven en
[docs/architecture.es.md](docs/architecture.es.md), y `build.zig` es el
cableado en sí.

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
const stark_mod = zk.module("zig-stark");
const snark_mod = zk.module("zig-snark");
```

## Primeros pasos

Los ejemplos viven junto al código que demuestran: el uso de `Transcript` y
`Channel` en el [README de transcript](libs/transcript/README.es.md), los
flujos de IPA y Pedersen en el [README de commitment](libs/commitment/README.es.md),
y el verificador de Groth16 y su prover de referencia en los comentarios del
módulo `libs/snark/src/root.zig`.

## Ejecutar las pruebas

El build raíz es el canónico: cablea todos los módulos y ejecuta todas las
suites, y resuelve `zig-algebra` desde el tarball pinneado, así que funciona
desde un clon limpio.

```bash
# Probar todas las librerías (compila Y ejecuta todas las suites)
zig build test --summary all

# Lo mismo, optimizado: la suite de snark, llena de emparejamientos,
# igual, optimizado. La suite de snark se ejecuta en ~60s en Debug y ~2s en
# ReleaseFast, pero una compilación en frío de ReleaseFast cuesta casi lo mismo
# que la corrida en Debug porque compilar el pairing es casi todo ese ~55s. La
# ganancia está en la ejecución, no en la compilación; el ~2s es con la caché.
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
