# zig-zk

> Español. [English version](README.md)

![CI](https://github.com/samooth/zig-zk/actions/workflows/ci.yml/badge.svg)

Un ecosistema de protocolos criptográficos y pruebas de conocimiento cero para
Zig, construido sobre `zig-algebra`.

Requiere Zig 0.16 y `zig-algebra` **v0.6.0** (fijado por huella en
`build.zig.zon`). El pin es lo que la compilación resuelve de verdad, así que esta
línea es una afirmación sobre él, y `zig build check-contract` falla cuando las dos
se contradicen.

## Estado

Esto es una biblioteca en workings, no una terminada. La tabla de abajo es un
resumen, y [TODO.es.md](TODO.es.md) es la fuente: `check-docs` falla cuando las
dos no coinciden, y una fila que dice `hecho` en `TODO.es.md` y falta aquí también
es un fallo, así que un trabajo que aterrice en la fuente no puede dejar atrás esta
sección.

Cinco estados, no dos. Una casilla binaria borra los tres intermedios que quien
llega aquí necesita ver: algo medido con la decisión todavía abierta no es lo mismo
que algo que no se ha intentado, y ninguna de las dos es lo mismo que un `hecho` cuya
puerta es lo único que lo mantiene cierto.

| Parte | Estado | Commit | Puerta |
|---|---|---|---|
| Completar la auditoría de `libs/signature` | a medias | - | - |
| Hash-to-curve | sin empezar | - | - |
| BLS12-381 | sin empezar | - | - |
| Multifirma y umbral de Schnorr | sin empezar | - | - |
| Ed25519 sobre campo primo | sin empezar | - | - |
| Adaptadores de punto para otras curvas | sin empezar | - | - |
| DER, PEM y formatos de intercambio | sin empezar | - | - |
| Propagar `allow_small_field` | hecho | `0d81e3a` | `zig build test` |
| El número de rondas | medido, falta decidir | - | - |
| La raíz duplica el cableado de cada librería | a medias | - | - |
| Higiene del pin | hecho | `727c46d` | `zig build check-contract` |
| `core/hash` y `core/merkle` | sin empezar | - | - |
| Afirmaciones de tiempo constante, con puerta | hecho | `8946c6b` | `zig build check-contract` |
| Hash dentro del circuito | sin empezar | - | - |

Los estados negativos son baratos de mantener, y esta tabla está escrita a mano por
eso: afirmar que algo no ha empezado no puede pudrirse en dirección dañina, porque
lo peor que puede pasar es que la tabla se quede conservadora. Un `hecho` es la
afirmación cara, y lleva el commit que lo cerró y la puerta que se pondría roja si
dejase de ser cierto. Un `hecho` sin celda de puerta lo rechaza `check-contract`.

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

## Contrato de validación

Qué es cada puerta aquí, y qué no es. Una puerta que dice lo que no cubre es
usable; una que sólo dice lo que cubre se lee como una garantía de todo.

`zig build test` es el punto de entrada, y depende de `check-docs` y de
`check-contract`, así que una pasada completa son las tres. Es una **garantía
sobre las aserciones de la batería y sobre las reglas de las dos puertas**. No es
una demostración de nada: no que la batería cubra lo que importa, no que los
protocolos sean correctos, no que el código no tenga defectos. Las pruebas de
fuzz ejecutan un número acotado de iteraciones, así que una pasada verde es una
muestra y no una ausencia.

| Puerta | Garantiza | No garantiza |
|---|---|---|
| `zig build test` | Toda aserción de la batería se cumple; 302 pruebas sobre 36 pasos | La cobertura, la corrección de los protocolos, la ausencia de defectos |
| `zig build check-docs` | Que todo fichero markdown tiene su pareja en la otra lengua; que cada uno declara su lengua y enlaza a su pareja; que ninguna prosa lleva palabras del otro idioma; que ningún CJK, kana o cirílico llega a la prosa; que las versiones del changelog descienden sin repeticiones ni cuerpos vacíos; que los ficheros emparejados llevan el mismo número de secciones; que una fila de estados tiene cuerpo; que una fila cerrada nombra el commit que la cerró y sigue diciendo lo mismo allí; que la tabla de estado del README concuerda con `TODO.es.md` en las dos direcciones | Que la prosa sea correcta, que una traducción sea buena, o que una afirmación en prosa sea cierta. Las cifras y los estados se comprueban. La prosa no |
| `zig build check-contract` | El contrato declarado con `zig-algebra`: recuento de aserciones por zona contra un libro mayor dentado, el conjunto de módulos importados contra el declarado, cada manifiesto fijando la versión del libro, cada módulo cableado importado por algo, el pin nombrando una etiqueta publicada y no más de una versión por detrás, el total de pruebas recalculado desde el fuente, las afirmaciones de tiempo constante declaradas con el canal que filtran, y los recuentos de la documentación de stark contra el mismo fuente | Que los algoritmos sean seguros, o que el libro mayor describa la intención correctamente. Comprueba la declaración, no el mundo |
| `zig build check-pins-fresh` | Que `scripts/algebra-tags.txt` sigue igual que las etiquetas publicadas aguas arriba | Nada sin red, y por eso no es dependencia de `zig build test`: una puerta que sale a la red da un resultado distinto en CI que en un portátil |
| `zig build refresh-algebra-tags` | Nada. Escribe la referencia desde la red y no es una puerta | - |
| `zig build check-release` | Que el tag `v<versión>` existe para la versión de `build.zig.zon`, que está anotado y firmado, que resuelve a un commit de `main`, y que el manifiesto de ese commit declara la misma versión | Que el CI estaba verde en el momento de cortar el tag. Lee cuatro cosas de git y lo ejecuta CI en los empujes de un tag, no `zig build test`: el tag no existe hasta después de que el CI esté verde, así que una regla sobre el tag no puede condicionar el commit anterior. En una clonación superficial falla en vez de saltarse, porque un control que deja de ejecutarse en silencio es peor que uno que no existe |

La distinción que importa al leer una pasada verde: `check-docs` y
`check-contract` son garantías sobre **las declaraciones del propio repositorio**,
y las declaraciones las escriben personas. Una fila puede estar mal en los dos
ficheros a la vez y pasar, porque la puerta compara dos documentos entre sí. Lo
que las puertas eliminan es la clase de defecto en que se editó un documento y
los demás no, que es la clase que aquí sí ocurrió.

## Convenciones

Las dos convenciones de abajo se comprueban, así que no son costumbres que haya
que mantener.

**Sin referencias por línea.** En los doce ficheros README hay cero referencias
con la forma `fichero.zig:123`. Un número de línea es una promesa sobre una
posición que cualquier edición rompe, y el arreglo es siempre borrar el número en
vez de actualizarlo, así que la referencia se pudre hasta convertirse en una
mentira que se lee como puntero. Enlaza el fichero.

**Los pares son idénticos en estructura.** Cada uno de los seis pares de README
lleva el mismo número de secciones de nivel 2:

| Pair | Level-2 sections | Lines EN | Lines ES |
|---|---|---|---|
| Root | 13 | 272 | 284 |
| `libs/commitment` | 7 | 156 | 161 |
| `libs/signature` | 8 | 143 | 141 |
| `libs/snark` | 7 | 163 | 171 |
| `libs/stark` | 11 | 240 | 249 |
| `libs/transcript` | 9 | 155 | 158 |

Un par que difiere en número de líneas es prosa traducida -- el inglés y el español
no parten igual -- y no una sección que falte en una lengua. Esa asimetría faltó
una vez, cuando un script falló a mitad y nunca escribió su fichero, y por eso
`check-docs` cuenta secciones. También comprueba la tabla de arriba contra los
ficheros, porque una cifra en prosa es una afirmación y una cifra en una tabla es
una medición.

## Principios de diseño

1. **Corrección primero**: toda la criptografía está verificada matemáticamente
2. **Sin dependencias externas**: solo la biblioteca estándar de Zig + zig-algebra
3. **Comptime primero**: todas las constantes se calculan en compilación
4. **Sin asignaciones**: solo pila cuando es posible
5. **Genérico**: los algoritmos funcionan sobre cualquier campo o curva mediante
   parámetros de comptime

## Licencia

MIT o Apache-2.0
