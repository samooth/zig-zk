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
