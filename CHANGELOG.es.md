# Registro de cambios

> Español. [English version](CHANGELOG.md)

Todos los cambios relevantes de zig-zk están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado sigue [SemVer](https://semver.org/lang/es/): en `0.y.z` el MINOR lleva
los cambios incompatibles y el PATCH solo cambios aditivos y correcciones. La
política está desarrollada en
[docs/architecture.es.md](docs/architecture.es.md#versionado).

## [Sin publicar]

### Añadido

- **`Channel.reset(etiqueta)`**, que devuelve un canal al estado en que lo dejó
  `init`. Un canal tiene estado, así que un prover y un verificador que compartan
  uno muestrean retos distintos y el verificador devuelve `false` sin error en
  ninguna parte, que es la peor forma que puede tener un fallo porque parece una
  prueba equivocada y no un canal equivocado. Dos canales con una etiqueta es la
  forma correcta; esto convierte la forma equivocada en algo recuperable en vez de
  misterioso.

- **`M31.random(rnd)`, `M31.toInt`, `M31.div`, `M31.eql`, `M31.inverse` y
  `M31.isZero`.** M31 era el único campo del árbol que no se podía pasar a nada que
  afirmara el `FieldTrait` del pin, y por eso `Transcript.squeezeField` lo rechazaba
  y `absorbField` no podía alcanzarlo. `random` rechaza en vez de reducir, porque
  una muestra plegada módulo 2^31 - 1 lleva dos valores al mismo elemento.


- Interoperabilidad de Groth16, en la dirección que decide si el verificador de
  este repositorio sirve para las pruebas de otros. `libs/snark` lleva ahora una
  clave de verificación, una prueba y una señal pública producidas por **snarkjs
  0.7.6** sobre BN254, y la suite verifica esa prueba con `verify`. También se
  comprueba el caso negativo: el mismo vector con una señal pública de 22 en vez
  de 21 debe rechazarse, sin lo cual un verificador que aceptase cualquier cosa
  sería indistinguible desde fuera.

  Los vectores se incrustan con `@embedFile` en vez de leerse en tiempo de
  ejecución, para que la comprobación no llegue a depender del directorio de
  trabajo, y los analizadores dividen por la `z` proyectiva en vez de suponer que
  es uno: un supuesto que por casualidad se cumple en el fichero versionado es
  justo lo que falla con la prueba de otro. `libs/snark/src/vectors/regenerate.mjs`
  es la receta, y deliberadamente no reproduce el fichero byte a byte, porque
  `powersoftau new` sortea aleatoriedad nueva; lo que una repetición garantiza es
  la forma, que es la parte que impide que el analizador se haya ajustado a un
  fichero afortunado.

  La dirección inversa -- que el prover de este repositorio produzca una prueba
  que snarkjs acepte -- se ha comprobado una vez y se cumple, incluida la
  convención de que `ic[0]` es el punto en el infinito. No la impone
  `zig build test`, porque convertiría un intérprete de Node en una dependencia
  de la suite.

### Corregido

- **`shamir.split` entregaba el secreto, y toda configuración en la que llegó a
  compilarse, ejecutarse y darse por buena era esa misma configuración.**

  Llamaba a `Scalar.random()` sin argumento. Ningún campo de este repositorio lo
  tiene: M31 no tenía `random`, y todos los campos del pin reciben un
  `std.Random`. Así que la función compilaba sólo contra escalares locales de
  prueba, y el de `shamir.zig` devolvía la constante `4`, con el comentario
  *"deterministic for testing"*.

  Así que el polinomio era siempre `secreto + 4x + 4x^2 + ...`: todos los
  coeficientes tras el secreto iguales a 4. Entonces cualquier parte única en
  cualquier `x` da `secreto = y - 4(x + x^2 + ...)`, porque quien tenga la
  parte conoce los coeficientes. La propiedad de umbral de Shamir no queda
  debilitada: queda **invertida**, y en vez de exigir `k` partes basta una. Una
  parte que tiene una parte tiene el secreto.

  Esto no es un fallo de compilación ni un default malo. Cada vez que esta
  librería se compiló, se ejercitó y se dio por buena, se estaba ejercitando
  exactamente en el modo que divulga el secreto, y ninguna prueba podía
  verlo, porque el doble de prueba era lo que protegía el defecto. El doble
  decía ser aleatorio y no lo era, y un doble que miente sobre ser aleatorio es
  peor que no tener doble: hace que código que nunca se ejecutó parezca código
  que se ejecutó.

  Tres cambios, y el tercero es el que importa. `split` recibe ahora la fuente
  como parámetro, porque quien construye un transcript quiere los coeficientes
  ligados a algo que pueda repetir. El escalar de prueba muestrea de verdad, por
  rechazo. Y una prueba afirma que dos repartos del mismo secreto difieren, que
  es la afirmación cuya ausencia dejó esto quieto durante la vida de la
  librería.

  Esa prueba cazó el mismo defecto en el primer intento del arreglo, en este
  mismo commit. El límite de rechazo se escribió `fromInt(64).value`, y
  `64 mod 7 = 1`, así que aceptaba el cero y nada más: todos los coeficientes
  seguían siendo la misma constante, y el código se leía como si estuviera
  comprobado. Un límite que parece un límite y no lo es es peor que no
  comprobar nada, porque se cumple por construcción y ocupa el sitio de uno que
  comprobaría algo. La misma forma ha aparecido cuatro veces en este
  repositorio -- aquí, en un `eql` que comparaba un elemento consigo mismo, en
  una comprobación polinómica tautológica, y en un supuesto `z == 1` de
  Groth16 -- y son un solo defecto, no cuatro.

  El defecto quedó anotado en los cinco puntos por los que un refactor futuro
  tendría que pasar para reintroducirlo: el comentario de documentación de
  `split`, el `random` que devolvía la constante, el límite de rechazo, la
  prueba que falta sin él, y la propiedad de umbral que la constante destruía.


- **Dos afirmaciones de solidez publicadas eran falsas, y se corrigieron en este
  fichero sin que el registro lo dijera.** Ambas quedan aquí restauradas tal como
  las dice el tag, para que el registro muestre qué entregó cada versión y no lo
  que después se creyó que debería haber entregado.

  La primera se publicó en **0.5.0**: a una extensión de ocho bits se le daba
  "alrededor del 0,4%, y se compone a lo largo de las rondas". La cifra por ronda
  es del orden de 2^-8, y los errores de las rondas se **suman** en vez de
  componerse, así que una cota escrita como producto era falsa en la dirección
  que favorece al sistema. La segunda se publicó en **0.5.1**, y también en
  0.5.0: "`k` es el número de rondas del prover y aquí no está medido, así que no
  se cita ninguna cifra". `k` lo proporciona quien llama, el prover hace
  exactamente muchas rondas, el verificador comprueba la cuenta, y la cuenta no
  depende del campo: medido sobre una extensión de ocho bits y otra de 128 es el
  mismo, que es el punto. El campo de extensión es la restricción que ata y no
  el número de rondas, ya que una sola ronda sobre ocho bits cuesta 2^-8 y
  ninguna elección de `k` la convierte en 2^-128. La misma afirmación falsa
  aparecía en ocho sitios entre los dos idiomas.

  Ninguna de las dos correcciones la impone una puerta, y ninguna se puede medir
  desde el árbol: una afirmación sobre solidez es aritmética, y el único
  instrumento es hacer la aritmética y escribir lo que salió. La formulación
  corregida está en `README.md`, `libs/stark/README.md`, `fuzz.zig` y en el
  propio mensaje de fallo de la puerta de contrato, que son los sitios que
  describen el código actual.

  Lo que estaba mal en las correcciones también merece quedarse escrito. `68645ec`
  arregló en sitio las entradas de 0.5.0, que es reescribir en silencio un
  registro publicado, y `bf7b300` revirtió después sólo lo que había hecho
  `36ab1c7`, dejando el primer arreglo en su sitio. El mensaje del revert
  informaba de "cero líneas borradas", medido contra `v0.5.1`, una base que ya
  arrastraba el daño, cuando el objeto era el contenido de la sección publicada
  de 0.5.0, que es el tag `v0.5.0`.

254 pruebas en 30 pasos.

- **`Transcript.squeezeField` leía `F.order`, que no existe en ningún campo de este
  repositorio ni del pin.** Compilaba sólo contra escalares de prueba que se habían
  inventado ese nombre. Ahora deduce el ancho de `F.MODULUS`, que todos los campos
  llevan, y `absorbField` comprueba `toInt` donde lo usa. Las dos funciones
  llamaban antes a `traits.assertField`, que exige `inv`, `div`, `pow` e `isZero` y
  no las declaraciones que justo después leen: una puerta que acepta lo que no
  puede soportar, que falla una línea después de la puerta que debía cazarlo.

- **`Circuit` y `Setup` en `snark` no eran `pub`.** `verify` se alcanzaba y `prove`
  no, así que el prover de referencia era inusable desde fuera del fichero donde
  está definido. Una palabra cada uno; las pruebas no lo notaron porque están en ese
  fichero.

- **El paquete raíz publicaba un módulo `zig-stark` que no compilaba.** La raíz
  duplica el cableado de imports de cada librería en vez de delegar en su
  `build.zig`, y a la copia le faltaba `zig-parallel`, así que `StarkInner` no lo
  encontraba. Nadie había compilado ese módulo: toda prueba pasa por
  `libs/stark/build.zig`, que lo cablea bien. Se añade `zig-parallel`, y
  `tests/published_api.zig` instancia ahora la pila para que la copia no vuelva a
  pudrirse en silencio. La duplicación sigue ahí y es la causa estructural;
  cerrarla significa que el build de cada librería sea el único cableado, que es un
  cambio de empaquetado y no algo que se haga de paso en una corrección.

- **El ejemplo de inicio rápido de `libs/stark/README.md` verificaba `false` sin
  error.** Creaba un canal y lo pasaba a `prove` y luego a `verify`. También nombraba
  `zs.m31.stark`, donde `zs.m31` es el campo y el espacio de nombres es `zs.stark`, y
  dejaba `claimed_fib` como `...` en vez del último valor de la columna 0.
  Corregido en los dos idiomas, y la versión corregida es la que ejecuta
  `consumer/src/main.zig`, así que el ejemplo se ejecuta en vez de describirse.

## [0.5.1] - 2026-09-29

252 pruebas en 30 pasos, frente a 242 en 0.5.0 y sin tocar una sola línea de
código de biblioteca: el diff desde `v0.5.0` son nueve ficheros y ninguno está
bajo `libs/*/src`. Así que esto es un parche, y la medición es la razón y no una
consecuencia.

### Corregido
- **La puerta de documentación** recorría el árbol con `Dir.walk`, cuyas rutas
  llevan el separador de la plataforma mientras que todos los prefijos de la
  puerta están escritos con barra, así que en Windows no encontraba casi nada y
  reportaba éxito sobre dos ficheros. El build ahora fija el directorio de
  trabajo de los dos pasos de puerta, y las dos puertas se niegan a hablar cuando
  no ven: la del contrato falla si no leyó ningún manifiesto, la de
  documentación falla salvo que encuentre las marcas de una raíz de repositorio
  e imprimir cuántos ficheros ha visto. Una puerta que encoge su entrada y sigue
  informando verde es peor que no tener puerta, porque parece una prueba.
- **Las reglas propias de la puerta de documentación no tenían pruebas.** Sólo
  corría como ejecutable, así que sus reglas sólo se ejercitaban con el fallo que
  pasara por allí. Ahora tiene binario de pruebas, como la del contrato de antes.
- **El total de pruebas de los documentos de arquitectura** estaba escrito a mano
  en dos sitios, y caducó en un idioma mientras el otro se corregía. Vive ahora
  como constante con trinquete en el libro mayor de la puerta del contrato, con
  los dos documentos comprobados contra ella, y las dos formas de fallo vistas
  caer.
- **Las entradas de Binius en el README de stark** describían una suite de fuzz
  cuando hay tres, dos de ellas diferenciándose sólo en el campo, y_presentaban
  `core/hash` y `core/merkle` como decididas cuando su adopción es una pregunta
  abierta esperando la misma comprobación de hash de ficheros que tardó la capa
  de campo.

### Añadido
- **Una segunda vuelta de fuzz de gadgets** sobre una extensión de 128 bits, junto
  a la rápida, sin tocar el default ni las 2000 vueltas. La afirmación de la
  suite ancha es la estrecha: el camino de 128 recibe testigos aleatorios, no que
  sea sound.
- **`-Dfuzz-wide-iters`**, para el número de vueltas de esa pasada. Cada vuelta es
  órdenes de magnitud más cara que la de ocho bits, que el repositorio ya
  registra como lenta en un comentario de las pruebas de extremo a extremo.
- **Una comparación de las dos multiplicaciones de la torre**, que dependen de la
  CPU del anfitrión. Su alcance está escrito en el fichero y no resumido en otro
  sitio, porque no puede cazar un defecto que ambas implementaciones compartan:
  el acuerdo no es corrección.
- **Una regla de documentación para CJK en la prosa.** Un rango, no un
  vocabulario, así que se dispara sobre la clase y no sobre las cadenas ya vistas.

### Docs
- `docs/architecture` tiene una tabla de lo que un verde no demuestra, con las
  cuatro formas en que este repositorio ha encontrado uno, y qué cierra cada una.
- La cota de solidez sobre una extensión de ocho bits se enuncia como suma y no
  como producto en los ocho sitios en que aparecía, y la cifra por ronda ha
  desaparecido: los errores de las rondas se suman, así que un campo estrecho se
  paga una vez por ronda y ningún número de rondas lo rescata. `k` es el número
  de rondas del prover y aquí no está medido, así que no se cita ninguna cifra.
  Binius compromete en un álgebra bilineal y no en un campo, que es lo que el
  texto dice ahora en vez de suponer un argumento de campo primo.

## [0.5.0] - 2026-09-28

Véase [SECURITY.es.md](SECURITY.es.md) para el hallazgo de solidez que corrige
esta versión. Es un aviso y no una línea del changelog, y la razón está al final
de ese documento.

### Changed (BREAKING)
- **zig-algebra** queda fijada en `0.5.2`. El Blake3 de
  `libs/hash/src/blake3.zig` no era BLAKE3 en `0.5.1`: su salida raíz
  recomprimía el estado ya comprimido en lugar del valor de encadenamiento de
  entrada, así que el resumen no coincidía con ningún vector canónico. El
  transcript de este repositorio importa ese hash, así que **los desafíos de
  Fiat-Shamir no se conservan al subir**. Una prueba hecha con `<= 0.5.1`
  verifica con `<= 0.5.1` y no verifica después, porque los desafíos cambiaron.
  Los compromisos no están afectados y nunca lo estuvieron:
  `libs/stark/core/hash/hash.zig` envuelve `std.crypto.hash.Blake3`.
- **stark/binius**: la PCS y el suma-producto locales desaparecen. Se confirmó
  que el suma-producto es idéntico byte a byte al adoptado en el valor, la suma
  declarada y seis rondas, codificando ambas pruebas y comparando bytes en vez
  de comparar veredictos. La PCS no lo era, y la diferencia era real: nuestro
  `commit` hasheaba dos veces cada hoja del Merkle, así que su compromiso era
  otra función y una prueba suya no la leía un verificador de la adoptada. El
  material comprometido de la versión anterior no es intercambiable.
- Los puntos de llamada de **stark/binius** nombran ahora `SumcheckUnsafe` y
  `CommittedMlePcsUnsafe`. El campo sobre el que se instancia la pila Binius es
  `Gf256 = TowerField(3)`, de ocho bits, y las entradas seguras exigen 128 bits y
  lo rechazan. El nombre está en el código y no en un comentario para que no se
  pueda leer como algo que no es.
- **stark/core**: se elimina `pool.zig` junto con su estructura `Pool`, que era
  una copia de la de `zig-algebra`. `zig-parallel` pasa a ser una importación
  declarada.
- La suite de extremo a extremo de Binius es cobertura de fontanería, no de
  solidez. El error de solidez de una ronda de suma-producto sobre un campo de
  ocho bits es del orden de 1/|F|, alrededor del 0,4%, y se compone a lo largo
  de las rondas. Véase la revisit de `binius` en el libro mayor.

### Fixed
- **stark/core/hash** queda fijado con vectores de respuesta conocida calculados
  con un BLAKE3 independiente, uno de los cuales abarca dos fragmentos porque el
  defecto que vigilan está en la ruta multicapa. `hash2`, por la que pasa cada
  nodo interno del Merkle, no tenía ningún vector conocido: solo se comprobaba
  que difiere de la concatenación de sus argumentos, que es una afirmación sobre
  este módulo y no sobre BLAKE3.
- Los compromisos de **stark/binius** quedan fijados con raíces conhecidas,
  también calculadas fuera. Un hash no puede comprobarse consigo mismo, y una
  ida y vuelta está de acuerdo consigo misma, que es por qué el doble hash
  sobrevivió a todas las pruebas de extremo a extremo que tuvo.

### Añadido
- **SECURITY.es.md**, el aviso sobre la derivación de desafíos, y su|English version](SECURITY.md).

### Docs
- `libs/stark/README` ya no lista ficheros que no tiene, y dice de dónde
  vienen ahora el suma-producto y la PCS.

## [0.4.0] - 2026-09-27

MINOR: las aserciones que protegían valores aportados por el llamante
devuelven errores tipados.

299 pruebas en 22 pasos. Veinticuatro aserciones pasaron a ser veintitrés
comprobaciones, y una de ellas no es una conversión.

### Cambiado (INCOMPATIBLE)
- **stark**: veintidós aserciones de la zona M31 y dos de `core` devuelven ahora
  errores en vez de desaparecer en ReleaseFast. `Univariate` devuelve
  `error.OutputLength` para un búfer del tamaño equivocado y
  `error.InputLengthMismatch` cuando dos entradas que deben coincidir no
  coinciden. `MerkleTree` devuelve `error.InvalidLeafCount` y
  `error.OutOfRange`. `CirclePoint.generatorWithOrder` y
  `CircleCoset.canonicHalf` devuelven `error.InvalidLogSize`: los dos reciben un
  `log_size` que llega desde `StarkParams`, y con 32 el desplazamiento del
  exponente desborda. `fri` devuelve `error.InputLength` para un codeword cuya
  longitud no es la del dominio, que es el que la prueba le entrega al
  verificador. Las transformadas del círculo devuelven `error.OutputLength`,
  `error.InputLength` o `error.MismatchedLength`, que se mantienen como tres
  porque el nombre es el diagnóstico con el que el llamante va a actuar.
- **stark**: `nttClassic` y `nttForward`/`nttInverse` devuelven
  `error.InvalidLength`. Sus dos aserciones decían lo mismo entre las dos, e
  `isPowerOfTwo(0)` ya devuelve falso, así que una comprobación cubre el
  fragmento vacío, una longitud impar y cualquier cosa más larga.

### Corregido
- **stark**: `circleEvalCoset` solo comparaba `coeffs.len` con `evals.len`
  mientras el bucle indexa el coset con la longitud de `evals`, así que un coset
  más corto se salía de él y se llevaba por delante la aserción de
  `CircleCoset.at`. El llamante recibía un fallo que señalaba el fichero
  equivocado y el motivo equivocado. Esa es una comprobación que faltaba, no
  una que se convirtiera, y solo apareció porque se estaban convirtiendo las
  aserciones de al lado y ejercitando sus caminos de error.
- **stark**: el `a.len <= 2` de `simdButterfly` se borra en vez de convertirse.
  Delegaba en `nttClassic` y era a la vez redundante y más débil que la
  comprobación de la función a la que llamaba, porque aceptaba longitud cero. Una
  comprobación redundante y más débil que su sustituta es peor que ninguna,
  porque aparenta ser validación. Por eso la cuenta de la zona baja tres donde
  se convirtieron dos aserciones.

### Documentación
- Dos aserciones del círculo pasan a la lista de invariantes del libro mayor y no
  se convierten. `CircleCoset.at` y `CircleDomain.get` reciben un índice que
  todos sus puntos de llamada derivan del propio tamaño del coset, en un bucle
  acotado por ese tamaño o como cero, así que un índice malo no es alcanzable
  desde un llamante ni de lejos desde una prueba. Convertirlas cascadearía una
  firma falible por el NTT para guardar un caso que no puede suceder.
- `primitiveRootOfUnity` se deja a propósito, dos veces en `M31` y una en
  `QM31`. Con `n == 0` la segunda comprobación, `(n & (n - 1)) == 0`, desborda
  `n - 1`, así que en ReleaseFast eso es aritmética rota que produce una raíz de
  unidad equivocada, no un diagnóstico que falta. Es la aritmética de campo que
  el prover usa en el camino caliente, y necesita su propio análisis.
- `AGENTS.md` ganó una regla para comprobar la rama antes de editar, no después.
  Dos veces en dos días se hizo un cambio en la rama equivocada y el gate solo lo
  notó porque el recuento de aserciones salió imposible.

## [0.3.0] - 2026-09-26

MINOR: el contrato del AIR se muda a la librería que lo consume, el módulo
`zig-air` desaparece, y la regla sobre aserciones deja de ser prosa.

289 pruebas en 22 pasos, en Debug y en ReleaseFast. Dos de ellas nunca se habían
ejecutado antes de esta versión: la suite de fuzz de Binius, que era un `main`
dentro de un binario de pruebas, y las cinco pruebas del canal, porque nada
forzaba que se analizara su fichero. Las dos van nombradas en Corregido.

### Cambiado (INCOMPATIBLE)
- **stark**: el contrato del AIR vive ahora en
  `libs/stark/m31/air/contract.zig`, donde `BoundaryAssertion` ya hacía falta, y
  `assertAir(Air, F)` lo comprueba en tiempo de compilación desde
  `GenericStark`. Nueve declaraciones obligatorias con sus firmas, dos más si
  `num_preprocessed > 0`, y cinco si `num_lookup_relations > 0`. Un AIR mal
  formado falla ahora donde se escribe, en vez de producir un error desde
  dentro del prover que nunca mencionaba lo que faltaba.
- **stark**: se borran `libs/stark/m31/air/{air,constraint,frame,trace}.zig`.
  Nada los importaba; solo se reexportaban y no se consumían.
  `zig_stark.m31.air_air`, `air_trace`, `air_frame` y `air_constraint` quedan
  sustituidos por `zig_stark.m31.air_contract`.
- **air**: se elimina el módulo `zig-air`. Sus cinco constructores (`Air`,
  `BoundaryConstraint`, `TransitionConstraint`, `EvaluationFrame`,
  `ExecutionTrace`) no los instanciaba nada: el prover funciona por convención y
  nunca los construyó, así que el framework publicado no era el que usaba el
  prover. Sustituye el import por `zig-stark`, cuyo
  `m31/air/contract.zig` documenta y comprueba lo que tendría que cumplir un
  segundo motor de STARK.
- **snark**: `Groth16(ic_wires, n_constraints, n_wires)` valida sus argumentos
  en tiempo de compilación en vez de con `std.debug.assert`, que desaparece en
  ReleaseFast: un sistema mal formado antes compilaba allí y fallaba en la
  primera prueba. Un hilo repetido o fuera de rango ahora hace fallar la
  compilación con un mensaje que nombra el argumento.
- **commitment**: los valores que aporta el llamante ahora son errores, no
  aserciones. `shamir.reconstruct` devuelve `error.NoShares`,
  `Ipa.innerProduct` e `Ipa.commit` devuelven `error.LengthMismatch`,
  `shamir.split` devuelve `error.InvalidThreshold` o `error.TooFewShares`, e
  `Ipa.verify` devuelve `error.MalformedProof` para una prueba cuyas dos mitades
  miden distinto.
- **stark**: `prove` y `verify` pueden devolver `error.InvalidParams` para unos
  `StarkParams` que no encajan entre sí, y `error.InvalidTrace` para una traza
  con la forma equivocada; `MultiplicityAir.generateTrace` devuelve
  `error.TraceTooShort` por debajo de cuatro filas. Las tres cosas eran
  aserciones.
- **transcript**: `Channel.sampleIndex` devuelve `error.EmptyRange` para
  `n == 0`, donde `log2_int(usize, 0)` no está definido y la aserción anterior
  desaparecía en ReleaseFast.

### Corregido
- **stark**: la suite de fuzz de Binius nunca se ejecutó. Sus 2000 vueltas
  vivían en un `pub fn main`, y un binario de pruebas sin declaraciones de
  prueba termina con éxito en milisegundos, así que el paso de la CI titulado
  «incl. fuzz» no la ejecutaba. Ahora es una prueba, pasa, y tarda unos tres
  minutos.
- **transcript**: las cinco pruebas de `channel.zig` nunca se compilaban, porque
  nada forzaba que el fichero se analizara y la raíz del módulo no tenía un
  bloque `test { std.testing.refAllDecls(@This()); }`. Las cuentas que faltaban y
  la regla que evita la repetición están en `docs/architecture.md`.
- **stark**: `proveWithPreprocessed` perdía 22 reservas cuando se rechazaban los
  parámetros de FRI, así que la comprobación se hace ahora antes de reservar
  nada. Lo encontró la prueba que detecta fugas.
- **stark**: la suite de fuzz imprimía su propio resumen con
  `std.debug.print`, que no le dice nada al corredor de pruebas.
- **commitment**: el README mostraba `shamir.split(allocator, secret, threshold,
  total, rng)`, una firma que nunca existió.

### Añadido
- **stark**: `M31.invChecked`, `QM31.invChecked`, `TowerField.invChecked` y
  `BinaryField.invChecked` devuelven `error.DivideByZero`. Se usan en los seis
  divisores de los caminos de verificación de M31 y de Binius cuyo valor viene de
  la prueba o de un desafío de Fiat-Shamir, donde si `inv(0)` respondiera 0 el
  término escalaría por cero en vez de fallar.
- **stark**: `-Dfuzz-iters` fija el número de vueltas del fuzz (2000 por
  defecto) en el build raíz y en el de `libs/stark`.
- **snark**: `libs/snark` recibe el `build.zig` y el `build.zig.zon` que las
  otras cuatro librerías ya tenían. Sin ellos, `zig build test` dentro de
  `libs/snark` compilaba en silencio el repositorio raíz.
- **ci**: un paso que compila y prueba cada librería con su propio `build.zig`,
  que antes no ejercitaba nadie.
- **build**: `scripts/check_contract.zig` y `zig build check-contract`, cableados
  como dependencia de `zig build test` para que la CI los ejecute. Sostiene un
  libro mayor de cada zona bajo `libs/` con su total de aserciones, cuáles son
  invariantes y en qué se apoyan esas claves; las cuentas están trinqueteadas, así
  que una solo se mueve cuando alguien edita el libro mayor y explica por qué.
  También fija la versión de `zig-algebra` y el conjunto de módulos importados a
  través de la frontera. La regla que hace cumplir es que una aserción que
  protege algo que aporta el llamante es un error tipado, y una que valida un
  invariante de un valor ya construido se queda como aserción. La alcanzabilidad
  no se puede inferir del código, así que el total alcanzable que imprime es un
  máximo: una zona que no declara invariantes no ha clasificado ninguna
  aserción.

### Documentación
- Toda librería tiene README, en los dos idiomas. La API de cada librería vive
  ahí; `docs/architecture.md` se queda con el grafo de módulos, las políticas, la
  postura de seguridad y las pruebas, y `ARCHITECTURE.md` con las decisiones y las
  convenciones. Antes la API estaba escrita en tres sitios a la vez, que es como
  una descripción de una funcionalidad eliminada sobrevive en la documentación.
- Cada README dice lo que su librería no hace, y `libs/snark/README.md` dice de
  entrada que su prover es un oráculo de pruebas: los factores de cegado los
  aporta quien llama, no es de tiempo constante, y todavía no tiene vectores de
  interoperabilidad.

