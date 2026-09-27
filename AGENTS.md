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

- Before editing anything, know which branch you are on: `git rev-parse
  --abbrev-ref HEAD`. The gate catches a change made on the wrong branch, but
  only because the counts came out impossible; this is the check that prevents
  it instead of noticing it.
- Comptime for monomorphisation: zero runtime cost.
- A generic type is declared with an explicit `return struct { ... };`.
- Do not reimplement what a dependency already provides. Delegating is less code
  and less risk of a bug.
- An assert that guards something the caller supplies is a typed error, and one
  that validates an invariant of an already-constructed value stays an assert.
  The axis is what the assert protects, not whether its function is `pub`:
  `coset.at` takes an index from the caller and `coset.half` checks a field of a
  value it was handed, and both are public. A total function keeps its assert and
  a checked sibling takes an error, which is what `M31.inv` and `invChecked` do.
- `zig-algebra` is consumed as a pinned package, so a version number is the only
  channel between the two repositories, and it runs one way. A zone that copies
  from `zig-algebra` instead of importing it, and every `std.debug.assert` in the
  tree, are recorded in the ledger in `scripts/check_contract.zig`.
  `zig build check-contract` (also a dependency of `zig build test`) enforces it:
  each zone declares its total, which asserts are invariants, and what those are
  keyed on, and every number is ratcheted, so a count only moves when a person
  edits the ledger and says why. A zone that declares no invariants has had none
  of its asserts classified, so the reachable total the gate prints is an upper
  bound, not a figure for how much work is left.
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
