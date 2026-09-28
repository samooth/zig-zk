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
| `zig-signature` | `libs/signature/src/root.zig` | algebra-traits, curve, hash, rng | — |
| `zig-snark` | `libs/snark/src/root.zig` | field, curve, pairing | — |
| `zig-stark` | `libs/stark/root.zig` | field | transcript |

## Librerías

La API de cada librería vive en su propio README, y los comentarios de
documentación del código llevan el detalle.

| Librería | Para qué sirve | Referencia |
|---|---|---|
| transcript | Transcripciones Fiat-Shamir: `Transcript`, `LabelledTranscript`, `Channel` | [README](../libs/transcript/README.es.md) |
| commitment | `Ipa`, compromisos de Pedersen, reparto de Shamir, protocolos Σ | [README](../libs/commitment/README.es.md) |
| signature | Schnorr genérico, Ed25519 sobre std, adaptadores de secp256k1 | [README](../libs/signature/README.es.md) |
| stark | Pilas de STARK M31 DEEP-FRI y Binius | [README](../libs/stark/README.es.md) |
| snark | Verificador de Groth16 y prover de referencia sobre BN254 | [README](../libs/snark/README.es.md) |

Lo transversal se reparte por tipo: el grafo de módulos, la política de
dependencias y versionado, la postura de seguridad y las pruebas están aquí,
mientras que las decisiones de unificación, el contrato del AIR y las
convenciones del prover de Groth16 viven en
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

El `build.zig` raíz es el canónico: cablea los cinco módulos más las suites e2e y
de fuzz de stark, y trae zig-algebra desde el tarball pinneado, así que funciona
desde un clon limpio. Los `build.zig` por librería existen para el trabajo
aislado y resuelven zig-algebra desde el mismo tarball pinneado.

El paso `test` de la raíz compila y ejecuta todas las suites: 248 pruebas
repartidas en transcript (20), commitment (16), signature (6), stark (162),
snark (11), el control del contrato (7), las tres suites de respuesta conocida
que vigilan la capa consumida de zig-algebra (3, 2 y 3), más las suites e2e
(16) y de fuzz (2) de stark.
`libs/stark/tests/fuzz.zig` da 2000 vueltas sobre tres gadgets con un asignador
que detecta fugas, y afirma que acepta y que rechaza en cada vuelta; la segunda
de sus dos suites hace lo mismo sobre una extensión de 128 bits con muchas menos
vueltas, porque un producto en una torre de 128 bits es lo bastante caro como
para evitarlo en Debug en otros puntos de este mismo fichero. Juntas tardan unos
tres minutos.

Una prueba en un fichero nuevo solo se ejecuta si algo fuerza que ese fichero
se analice: un bloque `test { std.testing.refAllDecls(@This()); }` en la raíz
del módulo, o una referencia al fichero desde una prueba. Sin eso, el corredor
compila un binario sin ninguna prueba y reporta un aprobado en milisegundos. El
canal de transcript y la suite de fuzz de Binius estaban los dos en ese estado,
así que las cifras de arriba son las que hay que comparar, no el número de
declaraciones `test` del árbol.

### Lo que un verde no demuestra

Un aprobado es una afirmación sobre lo que se ejecutó, no sobre lo que era
cierto. Éstas son las formas en que este repositorio ha encontrado un verde que
significaba menos de lo que parecía, cada una con lo que de verdad la cierra.

| Fallo | Qué parece | Qué lo cierra |
|---|---|---|
| La prueba nunca se ejecutó | Se añade un fichero, se declara su prueba, y el corredor informa un aprobado en milisegundos porque nada forzó el análisis del fichero | Un `test { std.testing.refAllDecls(@This()); }` en la raíz del módulo, o una referencia desde otra prueba |
| El código se ejecuta, pero ninguna entrada toma esa rama | Una función a la que se llama constantemente, y nunca por la ruta que importa. `mulRec` se llama en toda máquina, porque `mulFast` construye con ella sus tablas, y sin embargo en x86-64 ningún *producto* llega a ella por `mul`, que despacha a `mulFast` | Una prueba que recorra esa ruta concreta, no una que pase por donde pase. `libs/stark/tests/tower_mul.zig` |
| La comprobación miró en otro sitio | Todas las zonas informan cero y todos los módulos declarados sin usar, porque el directorio de trabajo no era la raíz del repositorio y el recorrido no encontró nada | Fallar cuando la entrada es inverosímil, y no sólo cuando discrepa: una puerta que no lee ningún manifiesto, o no encuentra ninguna marca del repositorio, lo dice |
| La comprobación pasó sobre menos entrada | "2 files, all paired" leído como documentación verificada, desde un recorrido que vio dos ficheros en un directorio que tiene dos | Decir qué ha mirado, y no llegar a aprobado por debajo de un mínimo |

La cuarta fila es la que menos palabras necesita para seguir siendo cierta: una
cifra en la salida es una afirmación, y una cifra que nadie compara no decora
nada.

El alcance de cada comprobación se enuncia una vez, junto a la comprobación, y no
se copia aquí. `tests/tower_mul.zig` es el ejemplo trabajado de una comprobación
deliberadamente estrecha que lo dice arriba del todo: compara las dos
multiplicaciones de la torre, y no puede cazar un defecto que ambas compartan,
porque el acuerdo entre dos implementaciones no es corrección. Repetir esa frase
en un segundo sitio sería una segunda copia de una afirmación, y este
repositorio lleva una versión borrando esas.

La CI ejecuta la suite en Debug sobre Linux, macOS y Windows mediante
`.github/actions/setup-zig`, que descarga el compilador desde ziglang.org
(resolviendo `master` a través de `download/index.json`).

## Cómo contribuir

1. Las librerías de protocolos van en `libs/<nombre>/` con un `build.zig` que
   exponga un módulo.
2. Toda dependencia nueva de álgebra se declara en el `build.zig` raíz y en el
   `build.zig.zon` de la librería; mantén sincronizado el grafo de módulos de
   arriba. Una librería nueva necesita un README, que es la referencia de su
   API.
3. Las pruebas afirman, nunca imprimen. Un `std.debug.print` en una prueba es un
   fallo: no reporta nada al arnés y puede imprimir `true` junto a una aserción
   que falla.
4. Un valor que viene del llamante es un error devuelto, nunca un
   `std.debug.assert`: las aserciones desaparecen en ReleaseFast, donde la
   llamada pasa entonces a hacer lo que sea sin avisar. Eso incluye los
   argumentos de los constructores, la forma de los fragmentos y todo lo que
   se divide. Los invariantes internos entre dos funciones de la misma
   implementación se quedan como aserciones, porque no hay a quién responderle.
5. Dividir por un valor que venía de una prueba usa la variante comprobada
   (`invChecked`), que devuelve `error.DivideByZero`. Un divisor cero en un
   camino de verificación depende de quien ataca: si `inv(0)` respondiera 0,
   el término escalaría por cero y la vuelta se daría por buena.
5. Ejecuta `zig fmt` y la suite completa antes de abrir un PR.
6. Cada fichero markdown necesita su pareja en el otro idioma, y
   `zig build check-docs` lo verifica.
