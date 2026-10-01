# TODO

> Español. [English version](TODO.md)

Trabajo abierto, ordenado por lo que cierra más casos de uso y no por lo que es más
fácil. Cada punto dice qué falta y cómo se ve "hecho", para que se pueda comprobar
en vez de interpretarse.

Nada de esto está hecho. La casilla está para marcarse, no para decorar.

## En qué punto está cada cosa

| Punto | Estado |
|---|---|
| Completar la auditoría de `libs/signature` | a medias |
| Hash-to-curve | sin empezar |
| BLS12-381 | sin empezar |
| Multifirma y umbral de Schnorr | sin empezar |
| Ed25519 sobre campo primo | sin empezar |
| Adaptadores de punto para otras curvas | sin empezar |
| DER, PEM y formatos de intercambio | sin empezar |
| Propagar `allow_small_field` | hecho |
| El número de rondas | medido, falta decidir |
| La raíz duplica el cableado de cada librería | a medias |
| Higiene del pin | hecho |
| `core/hash` y `core/merkle` | sin empezar |
| Afirmaciones de tiempo constante, con puerta | sin empezar |
| Ramas locales | a medias |
| `libs/fri` en `zig-zkml` | precondición satisfecha |
| Hash dentro del circuito | sin empezar |
| Un solo repositorio | sin empezar |

- **a medias** — empezado, y la parte hecha está escrita abajo.
- **sin empezar** — no se ha intentado nada.
- **medido, falta decidir** — la medición existe y el número está cerrado; falta la
  decisión, y una decisión no es una medición.
- **precondición satisfecha** — el bloqueo que lo hacía inmedible ya no está. Se
  puede empezar hoy y produciría un número.

---

## Seguridad

- [ ] **Completar la auditoría de `libs/signature`** · *a medias*

  La librería son tres ficheros — `ed25519.zig`, `schnorr.zig` y `root.zig` — y los
  tres se han leído. En el proceso aparecieron dos defectos, los dos en
  `SchnorrSignature`, y los dos están corregidos.

  Lo que sigue faltando no es la lectura sino la referencia externa: ningún esquema
  de aquí se ha comparado con una implementación escrita independientemente desde su
  especificación, que es la comprobación que cazaría una mala lectura y no una
  inconsistencia interna.

  **Hecho:** que todo esquema tenga una prueba que compara contra una
  implementación escrita desde su especificación, y una mutación que haya que cazar.

- [ ] **Hash-to-curve** · *sin empezar*

  Ausente. Sin él no hay esquema de identidad, ni ninguna construcción que ate un
  mensaje a una clave de forma verificable.

  **Hecho:** una implementación de RFC 9380 para cada curva sobre la que firma la
  librería, con los vectores de prueba publicados.

---

## Esquemas de firma

- [ ] **BLS12-381** · *sin empezar*

  Ausente. El pin trae el pairing de BLS12-381 — se leyó
  `libs/pairing/src/bls12_381.zig` para confirmarlo — así que la aritmética que el
  esquema necesita sí existe.

  Es el que más importa: es lo que hace posible la agregación, y el resto de la
  librería da por supuesto un campo sobre el que se pueda emparejar. Es también el
  punto que bloquea hash-to-curve, y ése es el argumento de orden para poner
  hash-to-curve primero.

  **Hecho:** firmas agregadas que verifiquen como una, sobre el pairing fijado.

- [ ] **Multifirma y umbral de Schnorr** · *sin empezar*

  Ausente. FROST o un equivalente es un caso de uso completo que hoy no está
  cubierto: firmar con un conjunto de partes de modo que ninguna parte por sí sola
  posea la clave.

  **Hecho:** que `k` partes produzcan una firma que verifique bajo la única clave
  pública, y una mutación que rompa la participación de Lagrange.

- [ ] **Ed25519 sobre campo primo** · *sin empezar*

  `std.crypto.sign.Ed25519` cubre el de 255 bits. No hay Ed25519 sobre BN254. Para
  una librería de ZKP eso es un hueco real, y la curva es la sobre la que esta
  librería ya hace aritmética.

  **Hecho:** firmar y verificar sobre BN254 contra los vectores de la RFC 8032, con
  la variante de 255 bits sigue delegando en la estándar.

- [ ] **Adaptadores de punto para otras curvas** · *sin empezar*

  `root.zig` construye un adaptador para secp256k1. No hay adaptador listo para
  BN254, BLS12-381 o pasta dentro de esta librería. El contrato de `Point` es `add`,
  `scalarMul` y `eql`, más una forma de hashear el punto: o un método `toBytes` o
  campos públicos `x` e `y`. Una curva que no ofrezca ninguna de las dos se rechaza
  en tiempo de compilación con un `@compileError` que nombra el tipo, que es el
  comportamiento previsto.

  **Hecho:** cada curva nombrada tiene adaptador, y el camino del error de
  compilación tiene una prueba que muestra que un punto que no encaja detiene la
  compilación en vez de producir un reto al que le falta el compromiso.

---

## Codificación

- [ ] **DER, PEM y formatos de intercambio** · *sin empezar*

  Ausente. `toBytes` devuelve `[65]u8` para un punto, vía `toUncompressedSec1`, y
  `[32]u8` para un escalar. Cualquiera que necesite interoperar con otra pila tiene
  que escribir primero el analizador.

  Aburrido, y necesario antes de que alguien fuera de este repositorio pueda usar
  la salida.

  **Hecho:** un lector DER o PEM que rechace lo que debe rechazar, probado contra
  los bytes de otra pila y no contra el codificador propio.

---

## Binius

- [x] **Propagar `allow_small_field`** · *hecho*

  `StarkInner` y `BiniusArgWith` reciben un `allow_small_field` de comptime, y cada
  uno elige `Sumcheck` o `SumcheckUnsafe` **y** `MlePcs` o `MlePcsUnsafe`. Las dos
  capas juntas a propósito: un protocolo que rechaza en el sum-check y muele en la
  capa de compromiso es peor que dejar cualquiera de las dos como estaba.

  Entradas nuevas, para que nada existente se mueva: `BiniusStarkChecked(F, E, CP,
  bool)`, `BiniusStarkSecure(F, E)`, `BiniusArgChecked(F, E, CP, bool)`. Los tres
  constructores antiguos pasan `true` y son lo que siempre fueron, y por eso el
  recuento de pruebas no cambió al aterrizar esto.

  **Lo que el indicador no es**, y que costó una aserción fallida establecer: no
  convierte la configuración en un tipo distinto. `SC` y `M` son declaraciones
  dentro del struct, no campos, así que dos configuraciones que sólo difieren en el
  indicador son el mismo tipo, y nada impide pasar una prueba construida con el
  sum-check seguro a un verificador construido con el inseguro. Eso es sólido —el
  formato de prueba es idéntico y el verificador inseguro acepta más—, así que es
  un interruptor de política y no una garantía de tipos, y `sumcheck` / `mle_pcs`
  se publican como tipos para que la elección sea inspeccionable y no repetida.

  **Sigue abierto, y es el resto de este punto:** si el valor por defecto se mueve
  es una decisión de producto con el 5,0× por ronda al lado. El indicador hace la
  decisión expresable; no la hace.

---

## Compilación

- [ ] **El número de rondas** · *medido, falta decidir*

  `proof.sumcheck.rounds.len` es `k`, y `k` está medido en 3 para `Gf256/Gf256` y 6
  para `Gf16/Gf2_128`. La cota es `k/|E|`, y `k` es de quien llama; el prover corre
  exactamente esas rondas, y los errores se suman en vez de compounding.

  El 5,0× es **una propiedad del ancho del campo, no de `allow_small_field`**. Es la
  razón entre las dos configuraciones que corre la suite de fuzz: `Gf256` sobre
  `Gf256`, una extensión de ocho bits, y `Gf16` sobre `Gf2_128`.
  `allow_small_field` es sólo el interruptor que permite a quien llama *nombrar* el
  extremo de ocho bits. Quítalo y no queda nada frente a lo cual ser 5,0× más
  rápido, y por eso la cifra no se puede собра para la pregunta del valor por
  defecto: uno de sus dos extremos está dentro de lo que se está cuestionando. Y
  `arg.zig` ya llama a esa configuración «fast in Debug», así que la velocidad es un
  artefacto de la aritmética de campo sin optimizar sobre menos bits, no una
  propiedad por la que merezca la pena decidir.

  Así que la decisión no es el factor. Es qué campos son de primera clase, y la
  suite rápida dice en voz alta que su extremo de ocho bits «no dice nada sobre
  soundness» y que sólo pressiona la fontanería, las formas de testigo y el rechazo
  de manipulación.

  **Hecho:** que la decisión esté escrita, nombrando los campos de primera clase. El
  número no es lo que decide.

- [ ] **La raíz duplica el cableado de cada librería** · *a medias*

  `build.zig` vuelve a declarar el cableado de módulos en vez de delegar en el
  `build.zig` de cada librería. La copia se había desincronizado — le faltaba
  `zig-parallel`, ya corregido—, así que hoy la duplicación es igual en vez de estar
  mal, y eso no es lo mismo que haber desaparecido.

  La Regla 5 vigila el síntoma: un módulo cableado en un fichero de build que
  ningún fuente importa es un problema. La causa es la duplicación, y cerrarla es un
  cambio de empaquetado, no una corrección de defecto.

  **Hecho:** que `build.zig` nombre las cinco librerías y ningún módulo, para que
  haya un solo sitio donde se pueda añadir un módulo.

- [x] **Higiene del pin** · *hecho*

  `scripts/algebra-tags.txt` es la lista versionada de tags publicados, que escribe
  `zig build refresh-algebra-tags` y que `zig build check-pins-fresh` compara contra
  lo de arriba. La Regla 6 de `check-contract` falla cuando el pin nombra una
  release que nadie publicó, o cuando va más de una versión por detrás de la más
  nueva.

  Dos detalles que no eran evidentes. "Una versión por detrás" es una **posición en
  la lista**, no una resta: `zig-algebra` no publicó ningún `v0.4.x` ni `v0.5.0`, así
  que `0.6.0 - 0.5.3` son siete versiones por aritmética de menor y parche y una por
  publicación, y una comparación de números fallaría en un repositorio sano. Y los
  dos pasos con red **no** son dependencias de `zig build test` a propósito, así que
  la puerta que corre sin red y la que comprueba la referencia son pasos distintos.

  El fallo para el que existía esto: el PRNG muerto estuvo en cuatro tags de
  `zig-algebra`, tres publicados y firmados, y dos repositorios se enteraron sólo
  cuando alguien subió el pin.

---

## Mantenimiento

- [ ] **`core/hash` y `core/merkle`** · *sin empezar*

  Copias de `zig-hash` y `zig-merkle`. Necesitan la misma verificación de hash de
  fichero que recibió la capa de campo. `core/merkle` lleva un enganche de
  acelerador de GPU que upstream no tiene — `.auto` y `.on`, con
  `error.GpuUnavailable`—, así que hay un coste de mantenimiento real en la decisión.

  **Hecho:** que cada uno se compare con upstream y que la decisión de mantenerlo o
  borrarlo esté escrita con lo que divergió al lado.

- [ ] **Convertir en puerta las afirmaciones de tiempo constante, y que los dos
  doc-comments sean honestos** · *sin empezar*

  Dos afirmaciones, y no son del mismo género. Las dos se comprobaron en el fuente
  antes de escribirlas aquí, porque «constant-time-ish» es exactamente la forma de
  afirmación que no se puede refutar.

  `m31/circle/point.zig:mulScalar` **no** es de tiempo constante, y no por el flujo de
  control: el número de ventanas es fijo, la extracción del dígito es un desplazamiento
  y una máscara, y no hay representación con dígito con signo, así que no existe rama
  por el signo que filtrar. Lo que filtra es `table[digit]`: un acceso a memoria en un
  índice que depende del secreto, un canal de caché y no una rama. Todos los centros de
  llamada del árbol pasan un escalar público, así que aquí no es alcanzable. El
  doc-comment dice ahora el mecanismo y la alcanzabilidad en vez de suavizar.

  **Hecho:** una puerta que falle si aparece una afirmación de tiempo constante en un
  doc-string o un comentario sin nombrar el mecanismo y sin comprobar los centros de
  llamada. `mulScalar` y la nota de no-tiempo-constante del `README.md` son los dos
  ejemplares. Esa nota dice a qué centros de llamada llega la limitación —verificar y
  probar con testigo público es irrelevante, probar con secreto longevo y firmar no—,
  porque una limitación documentada si no se lee como la razón por la que no se
  corrigió, y quien lee no puede distinguir una decisión de una demora.

- [ ] **Ramas locales** · *a medias*

  `backup-pre-rewrite` y `rebuild-OLD` apuntan al mismo commit, así que una de las
  dos sobra por inspección. `backup-pre-rewrite-0.5.0` es la única copia del
  historial reescrito antes de 0.5.0. `salvage-50cb942` ya cumplió su función, y se
  confirmó que el código que guardaba era idéntico al reconstruido.

  **Hecho:** que la rama redundante se borre y que la que es de verdad única se
  guarde a propósito o se suelte, con la decisión escrita.

---

## Fuera de este repositorio

No son trabajo de este repositorio. Se listan porque lo bloquean.

- [ ] **`libs/fri` en `zig-zkml`** · *precondición satisfecha*

  614 líneas de una implementación privada de FRI. La pregunta es si se borra y se
  usa la de `zig-algebra`, o si se conserva. La línea es la única cifra de aquí sin
  objeto contra el que comprobarla en este espacio de trabajo.

  Los dos caminos fijados que no llegaban a completarse están corregidos en
  `zig-algebra 0.6.0`, y el pin se movió aquí en la misma versión. Subir el pin es lo
  que hace la decisión medible y no una cuestión de opinión.

  **Hecho:** que las dos implementaciones se comparen y la decisión quede escrita.

- [ ] **Hash dentro del circuito** · *sin empezar*

  Sin empezar. Nada más de ninguna hoja de ruta de circuitos es alcanzable sin él:
  un circuito que no sabe hashear no puede probar una preimagen.

  Poseidon primero. Está escrito de forma genérica sobre un campo y sólo usa sumas y
  multiplicaciones por constante, que es lo que lo hace barato en un circuito. Los
  demás no, y no deberían prometerse en la misma respiración.

  **Hecho:** Poseidon constreñido dentro del circuito, con una prueba de dispositivo
  que un digest equivocado no pueda satisfacer.

- [ ] **Un solo repositorio** · *sin empezar*

  Cinco librerías, cinco `build.zig.zon` y una versión para el proyecto: la raíz está
  en `0.7.0` y cada librería en `0.1.0`. Hay un changelog, en dos lenguas, que cubre
  las cinco.

  Si comparten historial sigue abierto, y es una decisión más pequeña de lo que
  parece precisamente porque las librerías están en `0.1.0`, donde no se le debe
  compatibilidad a nadie, y la línea `0.x` de la raíz es lo único a lo que hoy puede
  fijarse un consumidor.

  **Hecho:** un historial, o una razón escrita por la que hay varios.
