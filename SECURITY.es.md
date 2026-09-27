# Política de seguridad

> Español. [English version](SECURITY.md)

## Qué es este proyecto

`zig-zk` es una caja de herramientas de librerías de protocolos criptográficos.
Los *verificadores* son implementaciones de referencia, escritas para ser leídas
y auditadas; los *provers* de este repositorio no son código de producción.

## Superficies soportadas

| Librería | Estado |
|---|---|
| `zig-transcript` | Implementación de referencia. Estándar, pequeña, revisada. |
| `zig-curve` (vía `zig-algebra`) | Dependencia externa, fuera del alcance aquí. |
| `zig-pairing` (vía `zig-algebra`) | Dependencia externa, fuera del alcance aquí. |
| Verificador de `zig-snark` | Implementación de referencia. La interoperabilidad con otras implementaciones de Groth16 **aún no** está cubierta por pruebas. |
| Prover de `zig-snark` | **Solo oráculo de pruebas.** No es de tiempo constante, los factores de cegado los aporta el llamante, y usa multiplicaciones por escalar individuales en lugar de sumas de múltiplos. No lo uses con secretos que te importen. |
| `zig-stark` (M31, Binius) | Árbol adoptado aguas arriba con dos adaptaciones documentadas (`ARCHITECTURE.es.md`). Verifícalo antes de usarlo. |
| `zig-commitment`, `zig-signature` | Componentes de caja de herramientas con cobertura de pruebas escasa. Revísalos antes de usarlos. |

## Qué consideramos una vulnerabilidad

- Un verificador que acepta una prueba inválida, o rechaza una válida, para un
  enunciado que le corresponde gestionar.
- Una transcripción que permita que dos mensajes distintos produzcan el mismo
  estado, o un desafío predecible.
- Un esquema de compromisos que filtre su factor de cegado o su valor.
- Una firma que verifique para el mensaje, la clave o el firmante equivocados.
- Cualquier uso de un secreto en una rama, en un índice de tabla o en una
  salida anticipada.

## Qué no consideramos una vulnerabilidad

- El comportamiento no constante en tiempo de los provers de referencia. Está
  documentado como tal en cada módulo.
- Que el prover de referencia produzca una prueba para un testigo que no satisface
  el circuito **cuando el prover conoce el trapdoor de la configuración**. Es
  inerente a Groth16: un prover que conoce el residuo tóxico puede probar
  cualquier cosa. La solidez es una propiedad de la ceremonia de configuración, no
  del código del prover.
- Características de rendimiento que no estén documentadas como garantía.

## Cómo informar

Informa en privado al mantenedor. Incluye el commit, la librería, un caso
reproducible y si el problema es de solidez, de corrección o de documentación.
Nos comprometemos a acusar recibo en una semana.

Por favor, no abras un issue público para un problema de solidez sin resolver.
