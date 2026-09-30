# zig-transcript

> Español. [English version](README.md)

Transcripciones Fiat-Shamir para pruebas de conocimiento cero no interactivas:
absorb-squeeze determinista y con estado, sobre Blake3, con separación de
dominios.

## Características

- **Tres tipos, tres propósitos** — `Transcript` (con contador), `LabelledTranscript`
  (cada operación lleva etiqueta) y `Channel` (duck-typed, la forma que espera
  `zig-stark`)
- **Absorciones con prefijo de longitud** — un valor absorbido no se puede
  partir ni unir sin cambiar el estado de la transcripción
- **Squeezes con contador** — dos squeezes seguidos nunca devuelven los mismos
  bytes
- **Desafíos de campo uniformes** — `squeezeField` rechaza los valores que quedan
  fuera del orden del campo, así que el resultado es uniforme y no está sesgado
- **Bifurcable** — `clone` da un estado independiente para una rama en paralelo
- **Entrada/salida de campos sin pasar por bytes** — absorbe y extrae elementos de
  campo directamente

## Instalación

Añade esto a tu `build.zig.zon`:

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.7.0.tar.gz",
        .hash = "...",
    },
},
```

Y luego en tu `build.zig`:

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-transcript", zk.module("zig-transcript"));
```

## Primeros pasos

```zig
const zt = @import("zig-transcript");

// Crear una transcripción ligada a una etiqueta de protocolo
var t = zt.Transcript.init("mi-protocolo-v1");

// Absorber el enunciado público
t.absorb(&bytes_publicos);
t.absorbField(F, compromiso);
t.absorbFieldSlice(F, &vector);

// Extraer un desafío
var buf: [32]u8 = undefined;
t.squeeze(&buf);
const c = t.squeezeU64();
const d = t.squeezeField(F);   // uniforme sobre F, por muestreo con rechazo
```

## Transcripción con etiquetas

Cuando cada paso necesite su propio separador de dominio:

```zig
var lt = zt.LabelledTranscript.init("mi-protocolo-v1");

lt.absorb("paso-1", datos1);
lt.absorbField("paso-2", F, elemento);
const c1 = lt.squeeze("desafio-1", F);
var buf: [32]u8 = undefined;
lt.squeezeBytes("desafio-2", &buf);
```

## Channel

El canal duck-typed que usa `zig-stark`. Absorbe cualquier cosa que tenga `SIZE`,
`toBytes` y `fromBytes`, y no necesita ningún trait de campo:

```zig
var ch = zt.Channel.init("zig-stark/m31");
ch.absorbDigest(hash);          // hace de puente con el tipo Digest de libs/stark
ch.absorb(columnas_trazy);
ch.absorbMany(&mas_columnas);

const idx = try ch.sampleIndex(n);  // uniforme en [0, n), error.EmptyRange si n == 0
var out: [32]u8 = undefined;
ch.sampleBytes(&out);
const v = ch.sample(u32);
```

## API

### `Transcript`

| Función | Descripción |
|---|---|
| `Transcript.init(label)` | Transcripción ligada a una etiqueta de protocolo |
| `t.absorb(data)` | Absorbe bytes, con prefijo de longitud |
| `t.absorbField(F, x)` | Absorbe un elemento de campo como 32 bytes en ordenlittle-endian |
| `t.absorbFieldSlice(F, xs)` | Absorbe un fragmento de elementos de campo |
| `t.squeeze(out)` | Extrae `out.len` bytes seudaleatorios; incrementa un contador interno |
| `t.squeezeField(F)` | Extrae un elemento de campo uniforme (muestreo con rechazo) |
| `t.squeezeU64()` | Extrae un `u64` |
| `t.squeezeU256()` | Extrae un `u256` |
| `t.clone()` | Bifurca el estado |
| `t.reset(label)` | Reinicia desde la etiqueta inicial |

### `LabelledTranscript`

| Función | Descripción |
|---|---|
| `LabelledTranscript.init(protocolo)` | Transcripción con etiqueta de protocolo |
| `lt.absorb(label, data)` | Absorbe bytes bajo una etiqueta |
| `lt.absorbField(label, F, x)` | Absorbe un elemento de campo bajo una etiqueta |
| `lt.squeeze(label, F)` | Extrae un elemento de campo bajo una etiqueta |
| `lt.squeezeBytes(label, out)` | Extrae bytes bajo una etiqueta |
| `lt.clone()` | Bifurca el estado |

### `Channel`

| Función | Descripción |
|---|---|
| `Channel.init(separator)` | Canal con separador de dominio |
| `ch.absorb(valor)` | Absorbe cualquier cosa con `SIZE`/`toBytes`/`fromBytes` |
| `ch.absorbBytes(data)` | Absorbe bytes crudos |
| `ch.absorbDigest(digest)` | Absorbe un `Digest` de `libs/stark` |
| `ch.absorbMany(valores)` | Absorbe varios valores en orden |
| `ch.sample(T)` | Muestrea un `T` del estado del canal |
| `ch.sampleIndex(n)` | Muestrea un índice uniforme en `[0, n)`, `error.EmptyRange` si `n == 0` |
| `ch.sampleBytes(out)` | Muestrea `out.len` bytes |

## Ejecutar las pruebas

```bash
zig build test --summary all
```

## Notas de diseño

- El estado es un resumen Blake3 en marcha. La función de resumen no es enchufable.
- Cada absorción lleva un prefijo de longitud `u64` en orden little-endian, así
  que `absorb("AB"); absorb("C")` y `absorb("A"); absorb("BC")` dan estados
  distintos.
- Cada squeeze añade un contador interno antes de finalizar, de modo que los
  squeezes repetidos avanzan el estado en lugar de repetirlo.
- `squeezeField` sortea hasta que el entero interpretado queda por debajo del
  orden del campo; el resumen rechazado se absorbe antes de reintentar, lo que
  mantiene el estado en marcha y la distribución uniforme.
- `libs/stark` usa `Channel` para sus desafíos de FRI. `libs/commitment` usa el
  patrón de esponja en su argumento de producto interno.

## Licencia

MIT o Apache-2.0
