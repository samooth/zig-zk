# TODO

> Español. [English version](TODO.md)

Trabajo abierto, ordenado por lo que cierra más casos de uso y no por lo que es más
fácil. Cada punto dice qué falta y cómo se ve "hecho", para que se pueda comprobar
en vez de interpretarse.

---

## Seguridad

### Completar la auditoría de `libs/signature`

La librería son tres ficheros — `ed25519.zig`, `schnorr.zig` y `root.zig` — y los
tres se han leído. En el proceso aparecieron dos defectos, los dos en
`SchnorrSignature`, y los dos están corregidos.

Lo que sigue faltando no es la lectura sino la referencia externa: ningún esquema de
aquí se ha comparado con una implementación escrita independientemente desde su
especificación, que es la comprobación que cazaría una mala lectura y no una
inconsistencia interna.

Hecho significa: que todo esquema tenga una prueba que compara contra una
implementación escrita desde su especificación, y una mutación que haya que cazar.

### Hash-to-curve

Ausente. Sin él no hay esquema de identidad, ni ninguna construcción que ate un
mensaje a una clave de forma verificable.

Hecho significa: una implementación de RFC 9380 para cada curva sobre la que firma
la librería, con los vectores de prueba publicados.

---

## Esquemas de firma

### BLS12-381

Ausente. El pairing ya está implementado en `zig-algebra`, así que la aritmética
que el esquema necesita existe.

Éste es el que más importa: es lo que hace posible la agregación, y el resto de la
librería da por supuesto un campo sobre el que se pueda emparejar.

### Multifirma y umbral de Schnorr

Ausente. FROST o un equivalente es un caso de uso completo que hoy no está cubierto:
firmar con un conjunto de partes de modo que ninguna parte por sí sola posea la clave.

### Ed25519 sobre un campo primo

`std.crypto.sign.Ed25519` cubre la variante del campo de 255 bits. No hay Ed25519
sobre BN254. Para una librería de ZKP eso es un hueco real, y la curva es
justamente aquella sobre la que esta librería ya hace aritmética.

### Adaptadores de punto para otras curvas

`root.zig` construye un adaptador para secp256k1. No hay adaptador listo para BN254,
BLS12-381 o pasta dentro de esta librería. El contrato de `Point` es `add`,
`scalarMul` y `eql`, más una forma de hashear el punto: o un método `toBytes` o
campos públicos `x` e `y`. Una curva que no ofrezca ninguna de las dos se rechaza en
tiempo de compilación con un `@compileError` que nombra el tipo, que es el
comportamiento previsto, y es el que documenta `libs/signature/README.es.md`.

---

## Codificación

### DER, PEM y formatos de intercambio

Ausente. `toBytes` devuelve 65 bytes para un punto y `[32]u8` para un escalar.
Cualquiera que necesite interoperar con otra pila tiene que escribir primero el
analizador.

Aburrido, y necesario antes de que alguien fuera de este repositorio pueda usar la
salida.

---

## Binius

### Propagar `allow_small_field`

`StarkInner` y `BiniusArgWith` siguen con `SumcheckUnsafe(E)` fijo en
`stark.zig:83` y `arg.zig:48`, y los seis constructores de conveniencia siguen
eligiendo `CommittedMlePcsUnsafe`.

Hecho significa: que el indicador llegue a las dos capas, y que entonces el valor
por defecto se pueda decidir sobre coste medido y no sobre la forma del código.

### El número de rondas

`proof.sumcheck.rounds.len` es `k`, y `k` está medido en 3 para `Gf256/Gf256` y 6
para `Gf16/Gf2_128`. La cota es `k/|E|`, y 128 bits cuestan 5,0× por ronda, lineal en
la suite de fuzz.

Lo que falta es la decisión: si el valor por defecto pasa a 128 bits es una decisión
de producto, y necesita escribirse con ese número al lado.

---

## Compilación

### La raíz duplica el cableado de cada librería

`build.zig` vuelve a declarar el cableado de módulos en vez de delegar en el
`build.zig` de cada librería. La copia se había desincronizado — le faltaba
`zig-parallel`, ya corregido—, así que hoy la duplicación es igual en vez de estar
mal, y eso no es lo mismo que haber desaparecido.

La Regla 5 vigila el síntoma: un módulo cableado en un fichero de build que ningún
fuente importa es un problema. La causa es la duplicación, y cerrarla es un cambio
de empaquetado, no una corrección de defecto.

### Higiene del pin

Nada comprueba que `build.zig.zon` coincida con los tags publicados de
`zig-algebra`.

El mismo fallo ya ocurrió una vez. Medido por etiqueta, el PRNG muerto está en
cuatro tags — `v0.5.0`, `v0.5.1`, `v0.5.2`, `v0.5.3` — de los cuales tres se
publicaron y firmaron, y la corrección es posterior a los cuatro. Los otros dos
repositorios se enteraron sólo cuando alguien subió el pin. Lo sostuvo que
`zig-rng` estuviera cableado en cuatro `build.zig` con cero imports fuera de
`libs/rng`, que es justo lo que hoy falla con la Regla 5.

Hecho significa: una puerta que falle cuando un pin vaya más de una versión por
detrás. Necesita una fuente de verdad para los tags publicados, que todavía no
existe, y eso es lo que tiene que venir primero: un umbral sin lista de tags con la
que comparar no es una puerta.

---

## Mantenimiento

### `core/hash` y `core/merkle`

Copias de `zig-hash` y `zig-merkle`. Necesitan la misma verificación de hash de
fichero que recibió la capa de campo. `core/merkle` lleva un enganche de
acelerador de GPU que upstream no tiene, así que hay un coste de mantenimiento real
en la decisión.

### Ramas locales

`backup-pre-rewrite` y `rebuild-OLD` apuntan al mismo commit.
`backup-pre-rewrite-0.5.0` es la única copia del historial reescrito antes de 0.5.0.
`salvage-50cb942` ya cumplió su función.

---

## Fuera de este repositorio

No son trabajo de este repositorio. Se listan porque lo bloquean.

### `libs/fri` en `zig-zkml`

614 líneas de una implementación privada de FRI. La pregunta es si se borra y se usa
la de `zig-algebra`, o si se conserva.

Los dos caminos fijados que no llegaban a completarse están corregidos en
`zig-algebra 0.6.0`. Subir el pin es lo que hace la decisión medible y no una cuestión
de opinión.

### Hash dentro del circuito

Sin empezar. Nada más de ninguna hoja de ruta de circuitos es alcanzable sin él: un
circuito que no sabe hashear no puede probar un preimagen.

Poseidon primero. Está escrito de forma genérica sobre un campo y sólo usa sumas y
multiplicaciones por constante, que es lo que lo hace barato en un circuito. Los
demás no, y no deberían prometerse en la misma respiración.

### Un solo repositorio

Cinco librerías, cinco `build.zig.zon` y una versión para el proyecto: la raíz está
en `0.7.0` y cada librería en `0.1.0`. Hay un changelog, en dos lenguas, que cubre
las cinco. Si comparten historial sigue abierto, y es una decisión más pequeña de lo
que parece precisamente porque las librerías están en `0.1.0`, donde no se le debe
compatibilidad a nadie, y la línea `0.x` de la raíz es lo único a lo que hoy puede
fijarse un consumidor.
