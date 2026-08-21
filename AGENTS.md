# AGENTS.md

Convenciones para agentes que trabajen en este repositorio. La documentación de
las librerías vive en `README.md`, `ARCHITECTURE.md` y `docs/architecture.md`;
esto son reglas de trabajo, no descripción del código.

## Git

- **El remoto es de la persona.** Prepara el trabajo y entrega el comando
  exacto. No publiques, no fuerces, no borres refs, no abras PRs.
- Un solo autor. El historial local (commits, ramas, tags, rebase) solo cuando
  se pida explícitamente.
- Commits y tags siempre firmados. Verifícalo con `git log --format='%G?'`: cada
  línea debe mostrar una firma válida.
- Mensajes en minúscula, estilo Conventional Commits. El cuerpo explica el
  porqué, no el qué.
- Publica un ref por push: un push con varios refs no es atómico.
- Si reescribes historia publicada, indica a quien ya clonó cómo actualizarse.

## Código

- Comptime para monomorfizar: cero coste en runtime.
- Un tipo genérico se declara con `return struct { ... };` explícito.
- No reimplementes lo que una dependencia ya ofrece. Delegar es menos código y
  menos riesgo de bug.
- Nada alcanzable desde la API pública puede depender de `std.debug.assert`:
  devuelve error explícito.
- Comentarios y doc-comments explican el porqué y lo no obvio.

## Tests

- Assert, nunca print. Un `print` dentro de un test no reporta nada al harness
  y puede mostrar `true` junto a un assert que falla.
- Antes de dar una suite por buena, comprueba que el número de tests que
  ejecutan es el esperado, y que el build realmente tiene step de test.
- Suite completa desde la raíz: `zig build test --summary all`.
- `zig fmt` antes de commitear.

## Documentación

- Se describe el código que existe, no el que se planea.
- Lo no obvio de un protocolo se escribe: la siguiente sesión no lo va a
  redescubrir.
- `CHANGELOG.md` sigue Keep a Changelog. SemVer, y en 0.x el MINOR se reserva
  para cambios incompatibles.
