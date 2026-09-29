# Registro de cambios

> Español. [English version](CHANGELOG.md)

Todos los cambios relevantes de zig-zk están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado sigue [SemVer](https://semver.org/lang/es/): en `0.y.z` el MINOR lleva
los cambios incompatibles y el PATCH solo cambios aditivos y correcciones. La
política está desarrollada en
[docs/architecture.es.md](docs/architecture.es.md#versionado).

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
  paga una vez por ronda y ningún número de rondas lo rescata. `k` resultó ser
  de quien llama y no del prover: el prover hace exactamente muchas rondas,
  el verificador comprueba la cuenta, y medido sobre una extensión de ocho bits
  y otra de 128 el número de rondas es el mismo, porque viene de la llamada y
  no del campo. Así que no hay un único `k` que citar, y el campo de extensión
  es la restricción que ata y no el número de rondas: una sola ronda sobre
  ocho bits ya cuesta 2^-8, que ninguna elección de `k` convierte en 2^-128.
  Por eso la entrada segura exige 128 bits de campo y no un número de rondas.
  La medición que corrigió esto es lo primero de aquí que fue un hecho y no una
  garantía, y está en el registro. Binius compromete en un álgebra bilineal y no
  en un campo, que es lo que el texto dice ahora en vez de suponer un argumento
  de campo primo.

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
  ocho bits es del orden de 1/|F|, y los errores de las rondas se suman en vez
  de multiplicarse: el total es una cota de suma del orden k/|F| para k rondas,
  no un producto. Así que un campo más estrecho se paga una vez por ronda, y
  ningún número de rondas vuelve adecuada una extensión de ocho bits: el campo
  tiene que cumplir |E| >= k * 2^lambda, y el que ata es el campo: una sola
  ronda sobre ocho bits ya cuesta 2^-8. `k` pertenece a quien llama, el prover
  hace exactamente esas rondas, el verificador comprueba la cuenta, y la cuenta
  no depende del campo. Una salvedad más:y
  aquí no está medido, y por eso no se cita ninguna cifra. Una salvedad más:
  Binius compromete en un álgebra bilineal y no en un campo, así que un
  argumento de solidez de campo primo no se traslada sin más. La entrada de
  `binius` en el libro mayor de divergencia, `scripts/check_contract.zig`,
  lleva la misma afirmación y el destino.

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

