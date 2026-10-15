# 016 — Amendment: swift-format ↔ SwiftLint Trailing-Comma Alignment (2026-04-29, 2026-06-24)

## Context

Every `make check` run dragged a flood of unrelated reformatting into the diff. The cause
was a genuine rule conflict between the two formatters:

- `.swiftlint.yml` set `trailing_comma: mandatory_comma: true`, and `make lint` ran
  `swiftlint --fix`, which strictly **adds** trailing commas to multi-line collection
  literals.
- swift-format 602 (the pinned local version / Swift 6.2 toolchain) actively **removes**
  trailing commas in multi-line collection literals whose last element is a multi-line
  function call; the `multilineTrailingCommaBehavior: alwaysUsed` knob that would change
  this only exists in swift-format 603+.

The two tools therefore oscillated forever: `swiftlint --fix` produced state A (commas),
any subsequent `swift-format` run flipped back to state B (no commas). Upstream supacode
had already untangled the same conflict (upstream commit `6dec82f2` "Align trailing comma
tooling"), but that commit never reached the fork.

## Change

**PR #248 (2026-04-29)** — mirror the no-toolchain-bump portion of upstream's fix:

- `.swiftlint.yml`: add `trailing_comma` to `disabled_rules`, remove the
  `mandatory_comma` block. swift-format becomes the single authority on trailing commas.
- `Makefile`: drop `swiftlint --fix` from the `lint` target — lint is a pure check;
  formatting belongs to `make format` / `make format-changed` (swift-format).
- Deliberately **not** adopting `multilineTrailingCommaBehavior: alwaysUsed`: swift-format
  602 silently ignores the unknown key, so the project standardizes on swift-format 602's
  natural fixpoint. To be revisited if swift-format is upgraded to ≥603.
- Verified idempotent at merge time: the full-tree sweep changed 0 files, so no bulk
  formatting commit was needed.

**PR #503 (2026-06-24)** — follow-up symptom of the remaining CI gap: two single-line
collection literals with trailing commas landed on `main` and made the full-tree
`swift-format lint --strict` step of `make check` fail locally, while CI stayed green
because the workflow only runs `make lint` (SwiftLint), not `make format-lint`. The PR
fixed the two violations; the CI gap itself was left open.

**Issue #575 (2026-10-13)** — closes the CI gap: the parallel `checks` task in
`.github/workflows/test.yml` runs `make format-lint` beside `make lint`, and
`.github/actions/setup-macos` links the selected Xcode's `swift-format` into a directory on
`PATH`, so CI uses the swift-format bundled with its pinned Xcode, the same one local
builds on that Xcode use. The checks task runs with `make -k`, so a SwiftLint failure no
longer hides format-lint results.

## Refs

- PRs #248, #503; upstream commit `6dec82f2` (provenance).
- `CLAUDE.md` records the resulting convention: "swift-format is the source of truth for
  trailing commas".

## Current state

As of 2026-07-12: `.swiftlint.yml` lists `trailing_comma` under `disabled_rules`; the
`Makefile` `lint` target is `swiftlint lint --quiet` (no `--fix`), `check` chains
`format-changed format-lint lint`, and `.github/workflows/test.yml` still ran only
`make lint`. Since #575 (2026-10-13) it runs both `make lint` and `make format-lint`.
