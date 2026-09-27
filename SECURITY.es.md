# Aviso de seguridad: los desafíos de Fiat-Shamir no se derivaban de BLAKE3

> Español. [English version](SECURITY.md)

**Afectado:** zig-zk `0.1.0` a `0.4.0`, es decir, toda versión construida contra
`zig-algebra` en la versión fijada `<= 0.5.1`.

**Corregido en:** la siguiente versión, fijando `zig-algebra` `0.5.2`.

**Gravedad:** los artefactos emitidos no son válidos bajo el análisis que
describe el protocolo. Desde fuera no pudimos determinar si eso es explotable, y
no saberlo es justamente el hallazgo.

## Qué ocurrió

La implementación de Blake3 en `libs/hash/src/blake3.zig` de `zig-algebra` no
era BLAKE3. Su salida raíz recomprimía el estado *ya comprimido* del último
fragmento en lugar del *valor de encadenamiento de entrada* y del bloque
original, que es lo que hace la referencia de BLAKE3. Los valores de encadenamiento
de los nodos no-raíz salían de una ruta correcta, así que la desviación quedaba
confinada al resumen final, y la función de compresión, el IV, el esquema de
mensajes y las banderas de separación de dominio sí eran BLAKE3. El resultado
era determinista y autoconsistente, y no coincidía con ningún vector canónico:

| entrada | `zig-algebra` en 0.5.1 | BLAKE3 |
|---|---|---|
| vacía | `5691d858…` | `af1349b9…` |
| `abc` | `605a5b03…` | `6437b3ac…` |

`zig-algebra` `v0.5.2` lo corrige. La corrección recomprime con el valor de
encadenamiento de entrada, y por eso la referencia conserva ese valor y el bloque
a mano en su estructura de salida.

## Qué hacía este repositorio con él

`libs/transcript/src/transcript.zig` importa `@import("zig-hash").Blake3`, así
que cada desafío de Fiat-Shamir que este repositorio derivó salió de esa
función. Un transcript es una esponja Blake3 y los desafíos se exprimen de ella,
de modo que los desafíos de las pruebas emitidas por `0.1.0` a `0.4.0` no son los
desafíos que el protocolo especifica.

Los compromisos **no** estaban afectados, y vale la pena separarlo porque las dos
cosas viajan juntas. `libs/stark/core/hash/hash.zig` envuelve
`std.crypto.hash.Blake3`, y el Merkle de `core/merkle` lo usa, así que todos los
compromisos que hizo este repositorio fueron BLAKE3 en todo momento. Solo los
desafíos no lo eran.

## Qué significa para una prueba que ya tienes

- Una prueba hecha con la versión fijada `<= 0.5.1` **verifica** con esa misma
  versión. La función es determinista, así que un verificador con el mismo código
  deriva los mismos desafíos, y nada del artefacto es detectable como malformado.
- Esa misma prueba **no verifica** tras subir a `0.5.2`, porque los desafíos
  cambiaron. Es la consecuencia habitual de cambiar un hash.
- Los argumentos de seguridad escritos para estos STARK dan por supuesto una
  esponja Blake3. No se aplican al software tal como se distribuyó.

Podemos acotar algo el daño: la desviación está solo en la salida raíz, así que
los valores de encadenamiento intermedios, y por tanto la estructura de los
compromisos y del transcript de Fiat-Shamir, se calcularon bien. Una ruptura
práctica parece improbable. No lo demostramos, y este aviso no certifica
solidez: una publicación no puede certificarla quien no puede ver el defecto.

## Cómo se encontró

Con un instrumental diferencial que comparó la PCS local contra la adoptada
**codificando ambas pruebas y comparando bytes**, sobre testigos aleatorios. Una
comparación de veredictos no habría mostrado nada: cada lado verifica su propio
artefacto a gusto, así que un defecto compartido parece un acuerdo. Los bytes
difieron, la diferencia se localizó en las rutas del Merkle, y al seguirla
apareció un segundo defecto en este repositorio —una hoja hasheada dos veces— más
el hash equivocado debajo.

Lo que hizo posible el resto fue un vector de respuesta conocida calculado con un
BLAKE3 **independiente**, en Python. Un hash no puede comprobarse consigo mismo,
así que los vectores de `libs/stark/core/hash/hash.zig`, uno de los cuales
abarca dos fragmentos porque el defecto está en la ruta multicapa, son lo único
en este repositorio que puede ver un hash equivocado.

## Qué hacer

Subir la versión fijada. El cambio es mecánico:

```
zig build --fetch
zig build test --summary all
```

No hace falta ningún cambio en el código, y ningún formato de prueba cambió más
allá de los desafíos descritos arriba.

El mismo hallazgo está reportado contra `zig-algebra`, que no puede verlo desde
dentro: la misma ceguera corre en el otro sentido, porque desde aquí nadie vio
que el transcript importaba el hash. Cada uno de los dos avisos está escrito
desde lo que su propio repositorio puede atestiguar, y cada uno apunta al otro.

## Por qué esto es un aviso y no una línea del changelog

Un hallazgo de solidez escondido en un changelog es un hallazgo de seguridad que
nadie busca. Este repositorio ya tiene uno, y de más de una forma: una nota de
publicación que afirmaba una publicación, un vector autogenerado indistinguible
de uno real, una disciplina de vectores que existía como práctica y no estaba en
ninguna lista. Una afirmación en prosa caduca; una prueba que se ejecuta no.
