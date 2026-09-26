# AGENTS.md

> Español. [English version](AGENTS.md)

Reglas de trabajo para agentes en este repositorio. La documentación de las
librerías vive en `README.md`, `ARCHITECTURE.md` y `docs/architecture.md`; este
archivo trata de cómo trabajar, no de lo que hace el código.

## Git

- **El remoto pertenece a la persona.** Prepara el trabajo y entrega el comando
  exacto. No publiques, no fuerces, no borres refs, no abras PR.
- Un solo autor. El historial local (commits, ramas, tags, rebase) solo cuando
  se pida explícitamente.
- Los commits y los tags van siempre firmados. Compruébalo con
  `git log --format='%G?'`: cada línea debe mostrar una firma válida.
- Mensajes en minúscula, estilo Conventional Commits. El cuerpo explica el
  porqué, no el qué.
- Publica un ref por push: un push con varios refs no es atómico.
- Si reescribes historia publicada, dile a quien ya la clonó cómo volver a
  sincronizarse.

## Versionado

- SemVer. En `0.x` el MINOR lleva los cambios incompatibles y el PATCH solo
  cambios aditivos y correcciones. La política está desarrollada en
  `docs/architecture.md`.
- La versión del manifiesto en `build.zig.zon` y el tag de git se fijan en el
  mismo commit de publicación, y el tag apunta a ese commit.

## Código

- Comptime para monomorfización: coste cero en tiempo de ejecución.
- Un tipo genérico se declara con un `return struct { ... };` explícito.
- No reimplementes lo que una dependencia ya aporta. Delegar es menos código y
  menos riesgo de fallo.
- Nada alcanzable desde la API pública puede depender de `std.debug.assert`:
  devuelve un error explícito.
- Los comentarios, incluidos los de documentación, explican el porqué y lo no
  obvio.

## Pruebas

- Aserción, nunca impresión. Una impresión dentro de una prueba no reporta nada
  al arnés y puede mostrar `true` junto a una aserción que falla.
- Antes de dar una suite por buena, comprueba que el número de pruebas que
  realmente se ejecutan es el esperado, y que la compilación tiene un paso `test`.
- Suite completa desde la raíz: `zig build test --summary all`.
- `zig fmt` antes de commitear.

## Documentación

- Describe el código que existe, no el que se planea.
- Escribe lo que no sea obvio de un protocolo: la siguiente sesión no lo va a
  redescubrir.
- Cada fichero markdown tiene su contraparte en el otro idioma: el nombre sin
  sufijo es inglés, `.es.md` es español, y cada fichero enlaza a su pareja en la
  cabecera. `zig build check-docs` (también dependencia de `zig build test`)
  verifica el emparejamiento, el idioma declarado y que los dos idiomas no se
  hayan mezclado.
- `CHANGELOG.md` sigue Keep a Changelog, y se versiona junto a las
  publicaciones que describe.
