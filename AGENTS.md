# AGENTS.md

> English. [Versión en español](AGENTS.es.md)

Working rules for agents in this repository. The library documentation lives in
`README.md`, `ARCHITECTURE.md` and `docs/architecture.md`; this file is about
how to work, not about what the code does.

## Git

- **The remote belongs to the person.** Prepare the work and hand over the exact
  command. Do not publish, do not force, do not delete refs, do not open PRs.
- One author. Local history (commits, branches, tags, rebase) only when
  explicitly asked for.
- Commits and tags are always signed. Check with `git log --format='%G?'`: every
  line must show a valid signature.
- Lowercase messages, Conventional Commits style. The body explains why, not
  what.
- Publish one ref per push: a push with several refs is not atomic.
- If you rewrite published history, tell whoever already cloned it how to get
  back in sync.

## Versioning

- SemVer. In `0.x` the MINOR carries incompatible changes and the PATCH carries
  additive changes and fixes only. The policy is spelled out in
  `docs/architecture.md`.
- The manifest version in `build.zig.zon` and the git tag are set in the same
  release commit, and the tag points at it.

## Code

- Comptime for monomorphisation: zero runtime cost.
- A generic type is declared with an explicit `return struct { ... };`.
- Do not reimplement what a dependency already provides. Delegating is less code
  and less risk of a bug.
- Nothing reachable from the public API may rely on `std.debug.assert`: return an
  explicit error instead.
- Comments and doc-comments explain why, and the non-obvious.

## Tests

- Assert, never print. A `print` inside a test reports nothing to the harness
  and can show `true` next to a failing assertion.
- Before calling a suite good, check that the number of tests that actually ran
  is the expected one, and that the build really has a `test` step.
- Full suite from the root: `zig build test --summary all`.
- `zig fmt` before committing.

## Documentation

- Describe the code that exists, not the code that is planned.
- Write down what is non-obvious about a protocol: the next session will not
  rediscover it.
- Every markdown file has a counterpart in the other language: the bare name is
  English, `.es.md` is Spanish, and each file links to its pair at the top.
  `zig build check-docs` (also a dependency of `zig build test`) verifies the
  pairing, the declared language, and that the two languages have not bled into
  each other.
- `CHANGELOG.md` follows Keep a Changelog, and is versioned with the releases it
  describes.
