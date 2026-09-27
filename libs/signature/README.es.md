# zig-signature

> Español. [English version](README.md)

Firmas digitales. Dos esquemas: un Schnorr genérico que funciona sobre cualquier
curva elíptica, y Ed25519 delegado a la biblioteca estándar.

## Características

- **Schnorr genérico** — `SchnorrSignature(Point, Scalar)` sobre cualquier grupo
  con `add`, `scalarMul`, `eql` y cualquier tipo escalar con `fromBytes`, `zero`,
  `add` y `mul`. Firmar y verificar son cinco líneas; lo interesante es que
  quien llama elige la curva.
- **Ed25519** — una reexportación fina de `std.crypto.sign.Ed25519`, que es
  determinista, de tiempo constante y ya auditado. Aquí no se reimplementa nada,
  porque las partes que importan —derivación del nonce, ajuste del escalar,
  verificación sin cofactor— son justo las fáciles de equivocar por un detalle.
- **Adaptadores de secp256k1** — `libs/signature/src/root.zig` adapta los puntos
  y escalares de `std.crypto.ecc.Secp256k1` a la interfaz genérica, que es lo que
  hace que Schnorr sea usable sobre la curva de Bitcoin.

No están: ECDSA ni BLS. Ed25519 está delegado en vez de escrito, y el mismo
razonamiento debería aplicarse a cualquier cosa que la biblioteca estándar ya
aporte.

## Instalación

```zig
.dependencies = .{
    .zig_zk = .{
        .url = "https://github.com/samooth/zig-zk/archive/refs/tags/v0.3.0.tar.gz",
        .hash = "...",
    },
},
```

```zig
const zk = b.dependency("zig_zk", .{});
exe.root_module.addImport("zig-signature", zk.module("zig-signature"));
```

## Primeros pasos

### Schnorr genérico

```zig
const sig_lib = @import("zig-signature");

// Point necesita: add, scalarMul, eql
// Scalar necesita: fromBytes, zero, add, mul
const Sig = sig_lib.SchnorrSignature(MyPoint, MyScalar);

// Firmar: R = k*G, e = H(G, P, R, msg), z = k + e*x
const firma = Sig.init(R, z);

// Verificar: z*G == R + e*P
if (!firma.verify(G, clave_publica, "mensaje")) return error.FirmaInvalida;
```

`challenge(base, public_key, R, msg)` está expuesto para que quien llama derive
el desafío con su propio resumen.

### Ed25519

```zig
const s = @import("zig-signature");

const kp = try s.KeyPair.generate();
const msg = "mensaje";
const firma = try kp.sign(msg, .{});
try s.PublicKey.verify(firma, msg, .{});

// Tamaños, para que quien llama no los lleve escritos a mano
comptime {
    _ = s.seed_length;         // 32
    _ = s.signature_length;    // 64
    _ = s.public_key_length;   // 32
}
```

## API

### `SchnorrSignature(Point, Scalar)`

| Función | Descripción |
|---|---|
| `Sig.init(R, z)` | Construye una firma a partir del compromiso y la respuesta |
| `firma.verify(base, clave_publica, msg)` | Comprueba `z*base == R + e*clave_publica` |
| `Sig.challenge(base, clave_publica, R, msg)` | Deriva el desafío con el resumen de la librería |

### Reexportaciones de Ed25519

| Nombre | Descripción |
|---|---|
| `Ed25519Impl` | `std.crypto.sign.Ed25519` en sí |
| `KeyPair` | Par de claves, con `generate()` y firmantes en streaming |
| `PublicKey`, `SecretKey`, `Signature` | Los tres tipos de la estándar |
| `seed_length`, `signature_length`, `public_key_length` | Tamaños en bytes |

## Ejecutar las pruebas

```bash
zig build test --summary all
```

## Notas de diseño

- El Schnorr genérico no lleva resumen propio: usa el que quien llama cablea al
  construir la firma, así que el mismo código funciona sobre un grupo de juguete
  en las pruebas y sobre secp256k1 en producción.
- `verify` devuelve un booleano y no un error, porque «firma incorrecta» es un
  resultado esperado y no excepcional.
- Los adaptadores de secp256k1 son privados del módulo a propósito: existen para
  demostrar que la interfaz genérica es usable sobre una curva real, no para
  ser API. Quien tenga su propia curva aporta su propio adaptador.
- Nada en este módulo es de tiempo constante salvo Ed25519, que es código de la
  biblioteca estándar. Un Schnorr genérico sobre un grupo aportado por quien
  llama hereda el comportamiento temporal de ese grupo.

## Licencia

MIT o Apache-2.0
