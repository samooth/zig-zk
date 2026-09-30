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

---


---

# Aviso de seguridad: los retos de Schnorr eran casi siempre cero y nunca ataban la clave

**Advertencia 2 de 2 -- ver arriba.**

**Afectado:** `libs/signature`, el `SchnorrSignature(Point, Scalar)` genérico,
tal como se publicó en `0.6.0` y en todas las versiones anteriores.

**Corregido en:** la siguiente versión. `0.6.0` está afectado, y este aviso es
parte de lo que llevará la siguiente.

**Gravedad:** cuatro firmas de cada cinco no comprometen ni la clave ni el
mensaje, y cualquiera puede producir una firma válida sin clave privada.

Ed25519 **no** está afectado. Va delegado a `std.crypto.sign.Ed25519` y nunca pasa
por `SchnorrSignature`. "La librería de firmas está rota" y "la mitad lo está" son
afirmaciones distintas, y ésta es la segunda.

## Una corrección al registro de 0.6.0, escrita después del tag

El changelog de `0.6.0` registra esto como "irrepetibilidad rota", en los términos
generales de la sección "no se atiende aquí", y lo aplaza a `0.6.1`. Eso es una
minimización por omisión, y el tag está firmado así que no se puede reescribir.
Omite dos cosas:

- **cuatro firmas de cada cinco**, no un caso raro: `P(rechazo) = 0,810969`, así
  que el promedio es 4,05 de cada 5;
- **dos mensajes distintos producen la misma firma byte a byte**, porque con
  `e = 0` el mensaje nunca llegó a la aritmética.

Un tag firmado que minimiza un P0 es peor que uno que no lo menciona, porque quien
lo lee decide con el número que tiene delante. Así que esta nota existe, y no
espera a que haya nombre de versión: es verdad ahora, y quien lea el changelog
después la encontrará aquí.

La siguiente versión llevará la entrada del changelog que dice todo esto.


## Dos defectos, independientes

**El reto era cero cuatro de cada cinco veces.** El código era

```zig
return Scalar.fromBytes(digest) catch Scalar.zero();
```

Para un campo más estrecho que el resumen, el resumen queda fuera de rango casi
siempre. El cuerpo escalar de BN254 tiene 254 bits y un resumen SHA-256 tiene
256, así que la muestra excede el módulo el **81,1%** de las veces, medido y no
estimado:

```
P(resumen >= módulo) = 1 - 21888242871839275222246405745257275088548364400416034343698204186575808495617 / 2^256
                    = 0,810969
```

La verificación es `s*G == R + e*P`. Con `e = 0` queda `s*G == R`, que cualquiera
satisface eligiendo `r`, poniendo `R = r*G` y `s = r`. En ninguna parte interviene
una clave privada. La demostración está en la suite y no usa ningún secreto.

Es peor que una firma falsificable: con `e = 0` el mensaje nunca llegó a la
aritmética, así que **dos mensajes distintos producen la misma firma byte a
byte**. Eso no es una firma débil, es una firma ausente.

**El reto nunca contenía la clave.** `hashPoint` comprobaba

```zig
if (@hasDecl(Point, "toBytes")) { ... }
else if (@hasDecl(Point, "x") and @hasDecl(Point, "y")) { ... }
```

`@hasDecl` informa de declaraciones, no de campos. `x` e `y` de un punto afín son
campos. Así que la segunda rama no podía tomarla ningún tipo, y un punto sin
declaración `toBytes` tenía las dos ramas falsas y **no hasheaba nada**: ni el
punto base, ni la clave pública, ni el compromiso del nonce.

## Por qué la suite pasaba

Los fixtures eligieron valores que hacían invisibles los defectos, que es la
quinta vez que en este repositorio una prueba no cazó nada por eso.

El fixture de `schnorr.zig` era un escalar de módulo 7 cuyo `fromBytes` leía un
solo byte y **no podía fallar**. Sin rechazo, nunca había reto cero.

La otra instanciación, en `root.zig`, es secp256k1, cuyo orden escalar queda
justo por debajo de `2^256`. Un resumen aleatorio de 32 bytes está por debajo
casi siempre -- la probabilidad de rechazo es del orden de `2^-224` -- así que
tampoco es visible para el segundo defecto.

Así que entre las dos, todas las instanciaciones del repositorio estaban donde
los defectos no podían mostrarse. La regla que sale de aquí, y que pertenece
junto a las demás en `AGENTS.md`: **un fixture tiene que elegir el valor que hace
visible el defecto, no el que hace fácil la prueba.** Un módulo pequeño hace que
la aritmética real no llegue a ejecutarse nunca.

## Qué es el arreglo, y por qué es de tiempo de compilación

`@hasDecl` pasó a ser `@hasField`, y un punto que no se puede hashear por ninguna
de las dos vías es ahora un `@compileError` en vez de un grupo que verifica
firmas en silencio sin la clave en el resumen.

El reto se reduce con `Scalar.fromInt` en vez de analizarse con `fromBytes`.
`fromInt` reduce y no tiene error que tragarse, así que el `catch` desaparece y
el fallo no se puede reintroducir por esa línea. Analizar era el contrato
equivocado desde el principio: un resumen de 32 bytes es una muestra uniforme, no
una codificación.

Tres pruebas de regresión, cada una confirmada por mutación sobre el código real:
el reto no es cero, y cambia cuando cambian la clave pública, `R`, el punto base o
el mensaje. La última es la aserción que faltaba y es la que importa: una
implementación que atara la clave pero no `R` seguiría permitiendo reutilizar un
nonce.

## Por qué esto es un aviso y no una línea del changelog

Porque una firma falsificable leída en un changelog es un hallazgo de seguridad
que nadie busca. `0.6.0` lo registró como "irrepetibilidad rota" y lo aplazó a
`0.6.1`, lo que se lee como trabajo rutinario. Se encontró desde fuera, por
alguien que montaba un demo sobre web/wasm, en un fichero donde todas las pruebas
habían pasado siempre.
