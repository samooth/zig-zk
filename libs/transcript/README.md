# zig-transcript

> English. [Versión en español](README.es.md)

Fiat-Shamir transcripts for non-interactive zero-knowledge proofs: deterministic,
stateful absorb-squeeze over Blake3, with domain separation.

## Features

- **Three types, three purposes** — `Transcript` (counter-based), `LabelledTranscript`
  (every operation takes a label) and `Channel` (duck-typed, the shape `zig-stark`
  expects)
- **Length-prefixed absorbs** — an absorbed value cannot be split or merged
  without changing the transcript state
- **Counter-based squeezes** — two consecutive squeezes never return the same
  bytes
- **Uniform field challenges** — `squeezeField` rejects values outside the field
  order, so the result is uniform, not biased
- **Forkable** — `clone` gives an independent state for a parallel branch
- **Byte-free field I/O** — absorb and squeeze field elements directly

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.2.2.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-transcript", zk.module("zig-transcript"));
```

## Quick Start

```zig
const zt = @import("zig-transcript");

// Create a transcript bound to a protocol label
var t = zt.Transcript.init("mi-protocolo-v1");

// Absorb the public statement
t.absorb(&bytes_publicos);
t.absorbField(F, compromiso);
t.absorbFieldSlice(F, &vector);

// Squeeze a challenge
var buf: [32]u8 = undefined;
t.squeeze(&buf);
const c = t.squeezeU64();
const d = t.squeezeField(F);   // uniform over F, by rejection sampling
```

## Labelled Transcript

When every step needs its own domain separator:

```zig
var lt = zt.LabelledTranscript.init("mi-protocolo-v1");

lt.absorb("paso-1", datos1);
lt.absorbField("paso-2", F, elemento);
const c1 = lt.squeeze("desafio-1", F);
var buf: [32]u8 = undefined;
lt.squeezeBytes("desafio-2", &buf);
```

## Channel

The duck-typed channel `zig-stark` uses. It absorbs anything with `SIZE`,
`toBytes` and `fromBytes`, and needs no field trait:

```zig
var ch = zt.Channel.init("zig-stark/m31");
ch.absorbDigest(hash);          // bridges stark's internal Digest type
ch.absorb(trace_columns);
ch.absorbMany(&more_columns);

const idx = try ch.sampleIndex(n);  // uniform in [0, n), error.EmptyRange if n == 0
var out: [32]u8 = undefined;
ch.sampleBytes(&out);
const v = ch.sample(u32);
```

## API

### `Transcript`

| Function | Description |
|----------|-------------|
| `Transcript.init(label)` | Transcript bound to a protocol label |
| `t.absorb(data)` | Absorb bytes, length-prefixed |
| `t.absorbField(F, x)` | Absorb one field element as 32 little-endian bytes |
| `t.absorbFieldSlice(F, xs)` | Absorb a slice of field elements |
| `t.squeeze(out)` | Squeeze `out.len` pseudorandom bytes; bumps an internal counter |
| `t.squeezeField(F)` | Squeeze a uniform field element (rejection sampling) |
| `t.squeezeU64()` | Squeeze a `u64` |
| `t.squeezeU256()` | Squeeze a `u256` |
| `t.clone()` | Fork the state |
| `t.reset(label)` | Restart from the initial label |

### `LabelledTranscript`

| Function | Description |
|----------|-------------|
| `LabelledTranscript.init(protocol)` | Transcript with a protocol label |
| `lt.absorb(label, data)` | Absorb bytes under a label |
| `lt.absorbField(label, F, x)` | Absorb a field element under a label |
| `lt.squeeze(label, F)` | Squeeze a field element under a label |
| `lt.squeezeBytes(label, out)` | Squeeze bytes under a label |
| `lt.clone()` | Fork the state |

### `Channel`

| Function | Description |
|----------|-------------|
| `Channel.init(separator)` | Channel with a domain separator |
| `ch.absorb(value)` | Absorb anything with `SIZE`/`toBytes`/`fromBytes` |
| `ch.absorbBytes(data)` | Absorb raw bytes |
| `ch.absorbDigest(digest)` | Absorb a `Digest` from `libs/stark` |
| `ch.absorbMany(values)` | Absorb several values in order |
| `ch.sample(T)` | Sample a `T` from the channel state |
| `ch.sampleIndex(n)` | Sample a uniform index in `[0, n)`, `error.EmptyRange` when `n == 0` |
| `ch.sampleBytes(out)` | Sample `out.len` bytes |

## Running Tests

```bash
zig build test --summary all
```

## Design Notes

- The state is a running Blake3 hash. The hash function is not pluggable.
- Every absorb carries a little-endian `u64` length prefix, so `absorb("AB");
  absorb("C")` and `absorb("A"); absorb("BC")` differ.
- Every squeeze appends an internal counter before finalising, so repeated
  squeezes advance the state instead of repeating.
- `squeezeField` draws until the interpreted integer is below the field order;
  the rejected digest is absorbed before retrying, which keeps the state moving
  and the distribution uniform.
- `libs/stark` uses `Channel` for its FRI challenges. `libs/commitment` uses the
  sponge pattern in its IPA argument.

## License

MIT or Apache-2.0
