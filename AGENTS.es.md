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

- Antes de editar nada, saber en qué rama estás: `git rev-parse --abbrev-ref
  HEAD`. El gate detecta un cambio hecho en la rama equivocada, pero solo
  porque las cuentas salen imposibles; esta es la comprobación que lo evita en
  vez de limitarse a detectarlo.
- Comptime para monomorfización: coste cero en tiempo de ejecución.
- Un tipo genérico se declara con un `return struct { ... };` explícito.
- No reimplementes lo que una dependencia ya aporta. Delegar es menos código y
  menos riesgo de fallo.
- Un refactor que recorre un árbol no desciende en un directorio de dependencia
  vendorizada. `zig-pkg/` guarda paquetes descargados contra un hash de contenido,
  y ese hash es su único mecanismo de integridad: escribir dentro desincroniza el
  paquete respecto al manifiesto en silencio, y nada protesta hasta que algo lee
  un fichero que no es el que dice la versión fijada. La recuperación, si ocurre,
  es borrar el directorio y dejar que Zig lo descargue otra vez, y luego cotejar
  las dos copias byte a byte: una descarga verifica el hash y una comparación es
  lo único que demuestra que el árbol está entero. Una regla que depende de que
  salga un error de compilación no es una regla.

- Una aserción que protege algo que aporta el llamante es un error tipado, y una
  que valida un invariante de un valor ya construido se queda como aserción. El
  eje es qué protege la aserción, no si su función es `pub`: `coset.at` toma un
  índice del llamante y `coset.half` comprueba un campo de un valor que le
  dieron, y las dos son públicas. Una función total conserva su aserción y una
  hermana comprobada devuelve error, que es lo que hacen `M31.inv` e
  `invChecked`.
- `zig-algebra` se consume como paquete fijado, así que un número de versión es
  el único canal entre los dos repositorios, y ese canal va en un solo sentido.
  Toda zona que copie de `zig-algebra` en vez de importarla, y todo
  `std.debug.assert` del árbol, quedan registrados en el libro mayor de
  `scripts/check_contract.zig`. `zig build check-contract` (también dependencia de
  `zig build test`) lo hace cumplir: cada zona declara su total, cuáles de sus
  aserciones son invariantes, y en qué se apoyan esas claves, y todo número está
  trinqueteado, así que la cuenta solo puede moverse cuando alguien edita el
  libro mayor y explica por qué. Una zona que no declara invariantes no ha
  clasificado ninguna aserción, así que el total alcanzable que imprime el gate
  es un máximo, no una cifra de cuánto trabajo queda.
- Los comentarios, incluidos los de documentación, explican el porqué y lo no
  obvio.

- Un fixture tiene que elegir el valor que hace visible el defecto, no el que hace
  fácil la prueba. Un escalar de módulo 7 no puede cazar nada sobre un campo de
  254 bits, y un módulo justo por debajo de 2^256 no puede detectar nada sobre un
  resumen que lo excede. Ya ha pasado cinco veces aquí: `x^n` en un dominio de
  orden `n`, `fromInt(64)` en un campo de siete elementos, un `eql` que comparaba
  un elemento consigo mismo, el `findGenerator` sin mutación, y un `fromBytes` que
  leía un byte y por eso no podía fallar. La pregunta que hay que hacerle a un
  fixture no es si la prueba es fácil de escribir, sino qué defectos vuelve
  inalcanzables.

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
  versiones que describe.
- Una entrada ya publicada no se edita a posteriori, ni siquiera cuando está mal.
  Lo que dice el tag es lo que se entregó, y quien compara el changelog con un
  tag está usando esa diferencia para averiguar qué cambió; una entrada corregida
  en silencio en `main` se lee como un tag movido. La corrección va en la sección
  sin publicar, nombrando la versión que publicó el texto equivocado.
- Por eso el objeto de la comprobación viene del tag, no del commit anterior.
  "No he cambiado la sección publicada" medido contra el commit previo a tu
  trabajo sólo dice que hace una hora no la empeoraste, y sigue siendo cierto
  después de una reescritura silenciosa de dos commits antes. Que `git diff
  v0.5.0 -- CHANGELOG.md` salga con cero líneas borradas es la forma de la
  afirmación; una base que ya arrastra el daño convierte el número en
  una cifra sin objeto.
- Un nombre que ya significaba otra cosa no es una versión más pequeña de un
  nombre nuevo, y el compilador no lo dice cuando el otro está en otro ámbito. Un
  `Fp` local que sombrea el tipo de campo es un build en verde.
  publicaciones que describe.
