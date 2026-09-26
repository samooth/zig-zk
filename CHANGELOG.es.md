# Registro de cambios

> Español. [English version](CHANGELOG.md)

Todos los cambios relevantes de zig-zk están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/) y el
versionado sigue [SemVer](https://semver.org/lang/es/): en `0.y.z` el MINOR lleva
los cambios incompatibles y el PATCH solo cambios aditivos y correcciones. La
política está desarrollada en
[docs/architecture.es.md](docs/architecture.es.md#versionado).

## [0.2.2] - 2026-09-26

PATCH: nada de esto cambia una API pública. Documentación, licencia y archivos
de build que nunca estuvieron cableados.

### Corregido
- **build**: los `build.zig` por librería no podían compilar. Resolvían
  zig-algebra como dependencias por ruta (`../../zig-algebra`), lo que exige que
  ese repositorio esté clonado al lado del nuestro, y estaban escritos contra el
  antigua estructura de paquetes de zig-algebra (un paquete por módulo) que
  v0.3.x sustituyó.
  Ahora resuelven el mismo tarball pinneado que usa el build raíz, así que
  `cd libs/<nombre> && zig build test` funciona desde un clon limpio.

### Añadido
- `LICENSE-MIT` y `LICENSE-APACHE`. El README declaraba una licencia dual sin
  que existiera ninguno de los dos ficheros, así que realmente no se estaba
  otorgando ninguna licencia.
- `SECURITY.md`: qué superficies están auditadas, cuáles no, y —la parte que
  suele faltar— qué **no** cuenta como vulnerabilidad. En concreto, un prover de
  Groth16 que conoce el trapdoor de la configuración puede probar cualquier cosa;
  eso es una propiedad de la ceremonia de configuración, no un fallo del prover.
- `zig build check-docs`, un paso de compilación del que también depende
  `zig build test`: comprueba que cada fichero markdown tiene su pareja en el otro
  idioma, que cada uno declara su idioma, que la prosa de uno no se ha colado en
  el otro, y que los ficheros en español evitan los anglicismos con equivalente
  limpio en español.

### Cambiado
- **docs**: la documentación existe ahora en inglés y en español. El nombre sin
  sufijo es el inglés y su pareja en español añade `.es`. `AGENTS.md` y
  `ARCHITECTURE.md` solo existían en español y ahora tienen contrapartida en
  inglés.
- **docs**: `README.md` ya no anuncia KZG, ECDSA, BLS ni PLONK como si
  existieran. El diagrama de capas y las tablas de librerías coinciden ahora con
  `build.zig`.
- **docs**: las convenciones QAP de Groth16 se escriben una sola vez, en
  `ARCHITECTURE.md`, en lugar de dos.

## [0.2.1] - 2026-09-26

### Añadido
- **snark**: Groth16 sobre BN254. `verify` comprueba
  `e(A,B) == e(alpha,beta) * e(C,delta) * e(PV,gamma)`, valida los elementos de
  la prueba contra curva y subgrupo de orden primo, y rechaza una aridad de
  entradas públicas que no case con las codificaciones.
- **snark**: `Groth16(ic_wires, n_constraints, n_wires)`, un prover de
  referencia genérico en comptime para sistemas de restricción de rango 1:
  `Circuit`, `Setup`, `VerifyingKey`, `Proof`, `setup`, `prove`, `verifyKey` y
  `satisfies`, sobre matrices de restricciones en la pila.
- **snark**: `error.DegenerateSetup` (residuo tóxico a cero, `gamma == delta`, o
  un trapdoor dentro del dominio de evaluación) y `error.QapUnsatisfied` (el
  testigo viola una restricción, así que el numerador del QAP no es divisible por
  el polinomio que se anula en el dominio). Errores en lugar de
  `std.debug.assert`, que desaparece en ReleaseFast.
- **snark**: 11 pruebas basadas en aserciones que cubren el ciclo completo, las
  entradas públicas equivocadas, los elementos de la prueba manipulados o fuera
  de la curva, una configuración distinta, los factores de cegado, la aridad malformada y
  la bilinealidad del emparejamiento.
- `CHANGELOG.md`.

### Documentación
- `docs/architecture.md` describe el código que existe: API por librería, grafo
  de módulos, postura de seguridad, pruebas.
- `ARCHITECTURE.md` y `docs/architecture.md` registran las convenciones de
  Groth16 (semántica de `ic_wires`, la codificación del hilo constante uno en
  `ic[0]`, la suma de `c` solo sobre hilos privados) y la condición algebraica
  que verifica el emparejamiento.
- `README.md`: índice de documentación y ejemplo del prover de referencia.
- Doc-comments obsoletos corregidos en `zig-signature` y `zig-transcript`.

## [0.2.0] - 2026-08-26

### Añadido
- **stark**: el árbol canónico de zig-stark adoptado tal cual: la pila M31
  DEEP-FRI (FFT circular, NTT, polinomios univariantes, FRI, `GenericStark` con
  AIR ya resueltos) y la pila Binius (campos en torre, suma-producto, las variantes
  de PCS, la capa de argumentos, recursión con Poseidon2).
- **signature**: Ed25519 mediante `std.crypto.sign`, más adaptadores de
  secp256k1 para la interfaz genérica de Schnorr.
- **commitment**: reparto de secretos de Shamir, compromisos de Pedersen, Schnorr
  PoK y la prueba OR de CDS '94.
- **ci**: matriz Linux/macOS/Windows con una acción compuesta propia de
  `setup-zig`, y las suites canónicas e2e y de fuzz conectadas al paso `test` de
  la raíz.
- `AGENTS.md`: reglas de trabajo para agentes.

### Cambiado
- **stark**: el canal de Fiat-Shamir viene de `zig-transcript` en lugar de una
  copia propia; M31, CM31 y QM31 vienen de los campos de zig-algebra mediante
  `m31/builtin.zig`.
- **build**: el `build.zig` raíz pasa a ser la única entrada que cablea todos los
  módulos y ejecuta todas las suites.
- **commitment**: el argumento de producto interno deriva sus desafíos de una
  esponja Fiat-Shamir en marcha, así que el desafío de la ronda *k* ata el
  enunciado completo y todas las rondas anteriores.

### Dependencias
- **zig-algebra**: fijado como tarball publicado con huella de contenido, de modo
  que el repositorio compila desde un clon limpio sin ningún repositorio hermano
  presente.
