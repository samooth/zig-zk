# Arquitectura zig-zk

## Estratificación de repos

```
zig-algebra      primitivas matemáticas (sin protocolos)
   ↑ path-dep
zig-zk           protocolos zk: AIR · STARK · commitments · firmas · snark
```

- **zig-algebra**: campos (M31, CM31, QM31, BN254, BLS12-381, Pasta, binarios),
  curvas, pairings óptimos, MSM (Pippenger), KZG, hash, merkle, NTT, poly,
  transcript/Fiat-Shamir, FRI primitivo, linalg, serialization.
  Regla: nada de lógica de protocolos aquí.
- **zig-zk**: consume algebra por path-dep y aloja los protocolos.
  `libs/stark` aloja el árbol canónico adoptado de zig-stark@HEAD
  (M31 DEEP-FRI + Binius), con dos adaptaciones permanentes:
  1. Fiat-Shamir Channel vive en `libs/transcript` (port duck-typed del
     channel original; `absorbDigest(anytype)`).
  2. M31/CM31/QM31 vienen de `zig-algebra` field vía `m31/builtin.zig`
     (el antiguo dep por URL a samooth/zig-field está retirado).

## Decisiones sobre duplicados (auditoría post-adopción)

| Componente | Decisión | Motivo |
|---|---|---|
| Channel | **zig-transcript** (único) | Ya portado y validado; stark lo consume como módulo |
| core/hash (Blake3+Digest) | Se queda en stark | Tipo Digest fuertemente acoplado a merkle/FRI internos |
| core/merkle | Se queda en stark | Genérico sobre Digest; el merkle de algebra es byte-based |
| FRI | DEEP-FRI/circle en stark (producción); algebra/fri queda como primitiva educativa | Requisitos distintos; no forzar dedupe |
| m31/cm31/qm31 vendidos | **Eliminados** | Sustituidos por zig-algebra fields vía builtin.zig |

## Piezas de zig-stark NO adoptadas (producto congelado)

- `capi.zig` + `zig-capi.h`: ABI C del producto standalone.
- `cuda/*`: kernels GPU (WIP upstream).
Si alguna vez se reactúa zig-stark como producto, estos viven ahí;
zig-zk no los necesita.
