# zig-snark

> Español. [English version](README.md)

Groth16 sobre BN254: una primitiva de verificación y un prover de referencia.

**Léelo primero.** El verificador es el producto, y está pensado para que se
lea y se audite. El prover es un oráculo de pruebas: los factores de cegado los
aporta quien llama, no es de tiempo constante, y usa multiplicaciones por
escalar individuales donde un prover de verdad usaría sumas de múltiplos.
Existe para que el verificador tenga algo contra qué comprobar, no para
desplegarse.

## Características

- **Comprobación por emparejamiento** — `e(A,B) == e(alpha,beta) * e(C,delta) *
  e(PV,gamma)`: cuatro emparejamientos y una exponenciación, con una prueba de
  96 bytes.
- **Entrada no confiable validada** — los elementos de la prueba se comprueban
  contra curva y subgrupo de orden primo antes de usarlos, y se rechaza una
  aridad de entradas públicas que no case con las codificaciones. Ninguna de las
  dos cosas es paranoia: `zig-pairing` devuelve la identidad multiplicativa para
  los puntos fuera de la curva o del subgrupo, así que sin la comprobación un
  elemento falso borraría un término de la ecuación en lugar de hacer fallar la
  prueba.
- **Prover de referencia genérico en comptime** — `Groth16(ic_wires,
  n_constraints, n_wires)` deja las matrices de restricciones en la pila y no
  reserva memoria.
- **Un prover que rechaza testigos malos** — `prove` devuelve
  `error.QapUnsatisfied` en vez de producir una prueba para un testigo que viola
  una restricción. Calcular `A(tau)*B(tau) - C(tau)` sin comprobación da una
  prueba que *verifica* para cualquier afirmación, porque la ecuación de
  emparejamiento degenera entonces en una tautología.
- **Los parámetros mal formados se rechazan en tiempo de compilación** — un
  `ic_wires` vacío, un índice de hilo fuera de rango o un hilo repetido hacen
  fallar la compilación con un mensaje que nombra el argumento, en cualquier modo
  de optimización.

## Instalación

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.7.0.tar.gz",
        .hash = "...",
    },
},
```

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-snark", zk.module("zig-snark"));
```

## Primeros pasos

### Verificar

```zig
const snark = @import("zig-snark");

const ok = snark.verify(
    vk.alpha_g1,     // [alpha]_1
    vk.beta_g2,      // [beta]_2
    vk.gamma_g2,     // [gamma]_2
    vk.delta_g2,     // [delta]_2
    &vk.ic,          // codificaciones de las entradas públicas
    proof.a,
    proof.b,
    proof.c,
    &entradas,       // ic[1] * entradas[0], ic[2] * entradas[1], ...
);
```

`ic[0]` codifica el hilo constante uno; `ic[i + 1]` codifica la entrada pública
`i`. Un desajuste de longitudes devuelve falso.

### Provar (solo referencia)

```zig
// 3 restricciones, 5 hilos, hilos conocidos {0 = el uno constante, 2 = la salida}
const G16 = snark.Groth16(&.{ 0, 2 }, 3, 5);

const vk = try G16.setup(&circuito, setup);            // error.DegenerateSetup
const prueba = try G16.prove(&circuito, testigo, setup, blind_r, blind_s);
                                                                 // error.QapUnsatisfied
try std.testing.expect(G16.verifyKey(vk, prueba, .{salida}));
```

## API

### Funciones libres

| Función | Descripción |
|---|---|
| `verify(a1, b2, g2, d2, ic, pa, pb, pc, pub_in)` | La comprobación por emparejamiento; falso ante cualquier desajuste |
| `Groth16(ic_wires, n_constraints, n_wires)` | Prover de referencia para un R1CS de tamaño fijo |

### Tipos reexportados de zig-algebra

`Fr`, `G1`, `G2`, `Fp12T`, `g1_gen`, `g2_gen`. Se reexportan para que quien
llame no tenga que importar dos paquetes para una sola firma.

### Dentro de `Groth16(...)`

Estos tipos no son `pub`, así que quien llama los deduce con `const` en vez de
nombrarlos.

| Nombre | Descripción |
|---|---|
| `Circuit` | Matrices de restricciones `a`, `b`, `c`, por filas |
| `Setup` | `tau`, `alpha`, `beta`, `gamma`, `delta`; `isValid()` rechaza una configuración degenerada |
| `VerifyingKey` | `alpha_g1`, `beta_g2`, `gamma_g2`, `delta_g2`, `ic` |
| `Proof` | `a: G1`, `b: G2`, `c: G1` |
| `setup(circuit, setup)` | Precalcula las codificaciones de las entradas públicas |
| `prove(circuit, witness, setup, blind_r, blind_s)` | Produce una prueba |
| `verifyKey(vk, proof, public_inputs)` | La misma comprobación, con tipos |
| `satisfies(circuit, witness)` | Si el testigo cumple todas las restricciones |
| `Error` | `DegenerateSetup`, `QapUnsatisfied` |

## Ejecutar las pruebas

```bash
zig build test --summary all
```

La suite se basa en aserciones, y los casos negativos pesan tanto como el ciclo
completo: entradas públicas equivocadas, cada elemento de la prueba manipulado,
elementos fuera de la curva, una configuración distinta, factores de cegado
incluido el cero, aridad malformada, un testigo que no cumple el circuito, una
configuración degenerada, y la bilinealidad del emparejamiento comprobada contra
`powFast` — porque si el emparejamiento no fuera bilineal, todo lo demás sería
decorado.

La interoperabilidad está cubierta en la dirección que le importa a un
verificador. `src/vectors/` contiene una clave de verificación, una prueba y una
señal pública producidas por **snarkjs 0.7.6** sobre BN254, y la suite verifica
esa prueba con `verify`. Los vectores se incrustan con `@embedFile` en vez de
leerse en tiempo de ejecución, para que la comprobación no dependa del directorio de
trabajo, y los analizadores dividen por la `z` proyectiva en vez de suponer que
es uno, porque un supuesto que por casualidad se cumple en el fichero versionado
es justo lo que falla con la prueba de otro.

`src/vectors/regenerate.mjs` es la receta. No reproduce el fichero byte a byte:
`powersoftau new` sortea aleatoriedad nueva, así que un zkey regenerado, y con
él `vk.json` y `proof.json`, difieren de los versionados. Lo que sí garantiza una
repetición es la forma, que es la parte que importa, y por eso el analizador de la
comprobación no puede haber sido ajustado a un fichero afortunado.

La dirección inversa -- que el prover de este repositorio produzca una prueba
que snarkjs acepte -- se ha comprobado una vez y se cumple, incluida la
convención de que `ic[0]` es el punto en el infinito. **No** la impone
`zig build test`, porque convertiría un intérprete de Node en una dependencia de
la suite: trátalo como un resultado registrado, no como un trinquete.

## Notas de diseño

Las convenciones del QAP de las que depende este prover —el denominador de
Lagrange por par, `A(tau)` como interpolante de las evaluaciones por
restricción, `t(tau) * h(tau) = A(tau)*B(tau) - C(tau)`, la suma de `c` solo
sobre hilos privados, el significado de `ic[0]` y la condición algebraica que
verifica el emparejamiento— están escritas una sola vez en
[ARCHITECTURE.md](../../ARCHITECTURE.es.md), con la consecuencia de romper cada
una.

La multiplicación por escalar usa la escalera por ventanas en coordenadas
jacobianas de zig-algebra, no una implementación local.

## Licencia

MIT o Apache-2.0
