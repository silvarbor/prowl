# 065.003 — Bundled Skills Foundation (K1)

## Context

S0 confirmed that Prowl can distribute its own skills as direct directory symlinks, but the
shipped app still had no canonical skills bundle or shared registry. K1 establishes that
foundation for the later CLI installer, Settings UI, and 063 workflow materialization without
installing or modifying any skill in a user or project directory.

## Change

- `Makefile` now stages `skills/` into the ignored `Resources/skills/` directory through an
  `embed-skills` target using `rsync -a --delete`.
- `build-app`, `test`, `archive`, `benchmark-build`, and `bench` depend on `embed-skills`,
  matching the existing `embed-docs` lifecycle.
- `Resources/skills` is an Xcode folder reference in the app Resources build phase, so each
  shipped skill keeps its directory and `SKILL.md` layout under
  `Prowl.app/Contents/Resources/skills/<id>/`.
- `ProwlCLIShared` now exposes the Foundation-only `ProwlSkillAudience`, `BundledSkill`, and
  `ProwlSkills` registry. `bundled(resourcesURL:)` enumerates immediate skill directories in
  stable ID order, while `skill(id:resourcesURL:)` searches that enumeration instead of
  constructing an input-derived path.
- The minimal frontmatter parser reads required `name` and plain or `>-` folded `description`
  fields plus the nested `metadata.prowl-install` audience. Missing audience defaults to
  `user`; explicit `user` and `workflow` are accepted; any other value fails closed.
- `bundledForCLI(executableURL:environment:)` treats `PROWL_SKILLS_DIR` as a direct skills-root
  override. A present but invalid override does not fall back. Without the override, it resolves
  the executable symlink and locates `../skills` beside the bundled `prowl-cli` directory.
- `ProwlSkillsError` provides typed `BUNDLE_NOT_FOUND` and invalid-frontmatter failures for the
  later K2 command layer to map without parsing localized text.
- Clean CI stages `embed-skills` before parallel app tests, and the dedicated `test-cli-unit`
  target executes all non-integration SwiftPM tests before the socket integration suite.

## Decisions and boundaries

- K1 remains synchronous and Foundation-only. It adds no YAML dependency, installer, target
  detection, CLI command, socket behavior, Settings state, or write into an agent skill folder.
- Registry IDs are immediate directory names. Lookup filters the parsed registry, so values such
  as `../prowl-cli` cannot traverse out of the bundle.
- `PROWL_SKILLS_DIR` points directly at a skills root, whereas `bundled(resourcesURL:)` receives
  the app Resources root and appends `skills/`. The private common enumerator keeps this
  distinction explicit.
- Malformed audience metadata never defaults to `user`, preventing a typo from making a future
  workflow-only skill globally installable.

## Review hardening

- Clean CI originally staged only the CLI and docs before invoking `test-app`; because
  `Resources/skills` is ignored, the Xcode resource input was absent. The staging step now
  includes `embed-skills`.
- The CI integration filter compiled the registry tests but executed only socket integration
  tests. `test-cli-unit` now runs every non-integration CLI test and is part of the same CI task.
- Audience metadata now requires `prowl-install` to be a direct child of `metadata` and every
  metadata field to use one consistent direct-child indentation. Top-level, nested, and
  inconsistently indented forms fail before an audience can default or change.
- The invalid-audience fixture now includes an otherwise valid description and asserts the
  specific audience failure reason, so another invalid field cannot make the regression test
  pass accidentally.

## Verification

- TDD RED: the focused SwiftPM suite failed with 21 expected missing-symbol errors before the
  shared registry types existed.
- Review RED: two focused tests reproduced top-level audience metadata silently defaulting to
  `user` and nested audience metadata being accepted; 11 existing tests passed while both new
  tests failed for the expected reason.
- TDD GREEN: `ProwlSkillsTests` passed 14 tests covering plain and folded descriptions, default
  and explicit audiences, invalid/missing frontmatter, strict metadata hierarchy, stable
  sorting, safe ID lookup, override precedence and invalid-override behavior,
  executable-symlink resolution, and `BUNDLE_NOT_FOUND`.
- `make build-cli` and `make test-cli-smoke` passed.
- `make test-cli-unit` passed 75 unit tests, including all 14 registry tests.
- `make test-cli-integration` passed 97 integration tests.
- `make test` passed and the xcresult checks verified 2,621 main app tests plus 2 isolated shell
  cancellation tests with zero failures.
- `make check` passed, including strict Swift formatting, SwiftLint, and 44 script tests.
- `make build-app` passed with zero errors or warnings.
- The final Debug app contains
  `Contents/Resources/skills/prowl-cli/SKILL.md`; it is byte-for-byte identical to
  `skills/prowl-cli/SKILL.md`.

## Refs

- Slice: 065-K1
- Branch: `feat/bundled-skills-k1`
- PR: #729
- Depends on: [002-s0-skill-targets.md](002-s0-skill-targets.md)
