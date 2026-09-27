# Registro de cambios

> Español. [English version](CHANGELOG.md)

Todos los cambios relevantes de zig-zk están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado sigue [SemVer](https://semver.org/lang/es/): en `0.y.z` el MINOR lleva
los cambios incompatibles y el PATCH solo cambios aditivos y correcciones. La
política está desarrollada en
[docs/architecture.es.md](docs/architecture.es.md#versionado).

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

