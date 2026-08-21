# zig-transcript

Fiat-Shamir transcripts for non-interactive zero-knowledge proofs. Deterministic, stateful absorb-squeeze transcripts with domain separation.

## Features

- **Absorb-squeeze pattern** — standard Fiat-Shamir transform
- **Domain-separated labels** — each absorption is labeled for uniqueness
- **Pluggable hash backend** — Blake3 (default), SHA-256, Keccak
- **Challenge sampling** — bias-free challenge generation from transcript state
- **Clone and reset** — fork transcript state for parallel branches
- **Field element I/O** — absorb/squeeze field elements directly

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_transcript = .{
        .path = "path/to/zig-algebra-core/zig-transcript",
    },
},
```

Then in your `build.zig`:

```zig
const zt = b.dependency("zig_transcript", .{});
exe.root_module.addImport("zig-transcript", zt.module("zig-transcript"));
```

## Quick Start

```zig
const zt = @import("zig-transcript");

// Create a transcript
var transcript = zt.Transcript.init("my_protocol");

// Absorb data (with labels for domain separation)
transcript.absorb("message", message_bytes);
transcript.absorb("commitment", commitment_bytes);

// Squeeze a challenge
const challenge = transcript.squeeze("challenge_label");

// Squeeze field elements
const F = @import("zig-field").BN254_Fp;
const field_challenge = transcript.squeezeField(F, "field_challenge");

// Clone for parallel branches
var branch = transcript.clone();
branch.absorb("branch_data", data);
const branch_challenge = branch.squeeze("result");
```

## Labelled Transcript

For protocols requiring explicit domain separation at every step:

```zig
var lt = zt.LabelledTranscript.init("my_protocol");

lt.absorbLabel("step_1", data1);
lt.absorbLabel("step_2", data2);
const c1 = lt.squeezeLabel("challenge_1");
const c2 = lt.squeezeLabel("challenge_2");
```

## API

| Function | Description |
|----------|-------------|
| `Transcript.init(protocol)` | Create transcript with protocol label |
| `t.absorb(label, data)` | Absorb bytes with label |
| `t.absorbField(label, field_elem)` | Absorb field element |
| `t.squeeze(label)` | Squeeze 32-byte challenge |
| `t.squeezeField(F, label)` | Squeeze field element |
| `t.squeezeU64(label)` | Squeeze u64 |
| `t.clone()` | Fork transcript state |
| `t.reset()` | Reset to initial state |
| `LabelledTranscript.init(protocol)` | Create labelled transcript |
| `lt.absorbLabel(label, data)` | Absorb with explicit label |
| `lt.squeezeLabel(label)` | Squeeze with explicit label |

## Running Tests

```bash
zig build test
```

## Design Notes

- Transcript state is a running hash (Blake3 by default)
- Labels are encoded as length-prefixed strings for domain separation
- `squeeze` runs the hash function and returns 32 bytes of pseudo-random output
- `clone` copies the internal hash state for parallel protocol branches
- `reset` re-initializes the hash with the original protocol label
- Used by zig-stark (FRI challenges), zig-commitment (IPA challenges), and any ZK protocol

## License

MIT OR Apache-2.0
