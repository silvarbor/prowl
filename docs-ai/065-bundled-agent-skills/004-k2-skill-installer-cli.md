# 065.004 — Shared Symlink Installer and `prowl skills` (K2)

## Context

K1 (#729) put Prowl's official skills into the app bundle and gave the app, the CLI, and the
future workflow runner one registry, but nothing could yet link a bundled skill into an agent's
skill folder. The only symlink installer in the codebase was the `/usr/local/bin/prowl` logic
inside the TCA `CLIInstallClient`, and it could not see a dangling link (`fileExists` follows
symlinks). K2 extracts that logic into a shared Foundation-only installer, adds the three
verified S0 targets as declarative data, and ships the local-only `prowl skills` command group
with its contract, schema, manual, and skill line. Settings UI stays in K3.

## Change

- `SymlinkInstaller` (`ProwlCLIShared`) owns status/install/uninstall for one link slot. Status
  is `notInstalled` / `installed` / `installedDifferentSource` / `broken`; the slot is inspected
  with `attributesOfItem` (lstat) so a dangling link is `broken` instead of invisible. `install`
  creates parents, replaces live or dangling links, and refuses a real file or directory with
  `SymlinkInstallError.conflict` before any mutation; `uninstall` removes symlinks only.
  Filesystem errors other than the typed cases propagate unchanged.
- `CLIInstallClient` now delegates to the shared installer. `CLIInstallStatus` is a typealias
  of the shared enum; the user-facing messages, the osascript privilege fallback, and every
  existing `CLIInstallClientTests` case are unchanged. A dangling `/usr/local/bin/prowl` used to
  fail installation with a raw `EEXIST`; it is now reported as a broken link and repaired by
  Install. The Command Line Tool page gained the matching `broken` row (Repair button) because
  the shared enum is exhaustive; no other Settings work.
- `SkillInstallTarget.all` declares exactly `claude`, `codex`, and `agents` with their user and
  project directories. Detection is "the parent of the skills directory exists"; the same rule
  applies under a project root. `ProwlSkillInstaller` composes target + skill into one link
  slot (`<skills dir>/<skill id>` → bundled directory) for the CLI now and Settings in K3.
- `prowl skills list | install | uninstall | path` (`SkillsCommand` + `SkillsCommandExecutor`)
  runs entirely locally: it resolves the bundle through `ProwlSkills.bundledForCLI` from
  `Bundle.main.executableURL` (never bare `argv[0]`), reads the user root from `HOME`, and never
  touches `AppLauncher` or the socket. Bare `install` = every `user`-audience skill × every
  detected target; repeated `--target` selects and creates targets; `workflow` skills fail
  `SKILL_NOT_INSTALLABLE`; every slot is conflict-checked before any change so
  `INSTALL_CONFLICT` leaves nothing half-done; `uninstall` skips `not_installed` slots.
  Project scope takes `--path <repo>` or walks up from the cwd to the nearest `.git` entry (a
  worktree's `.git` file counts) and emits the absolute-path / `.git/info/exclude` note exactly
  once — `data.note` in JSON, one `note:` line on stderr in text mode.
- Contract layers: `prowl.cli.skills.v1` with `command: "skills"` and `data.action` as the
  discriminator (same shape as `create`/`handoff`), closed definitions in
  `cli-output-schema.json`, `docs-ai/013-prowl-cli/contracts/skills.md`, `input.md` and
  `schema.md` rows, a `prowl skills` section and error rows in `docs/components/cli.md`, and one
  line in `skills/prowl-cli/SKILL.md` telling an agent that `prowl skills install prowl-cli`
  keeps it current. The root `prowl --help` discussion also points at `prowl skills install`
  so a user or an agent discovers the bundled skills before any Settings UI exists.

## Decisions and boundaries

- One installer, not two: the CLI installer keeps only message mapping and privilege
  escalation. The shared status compares the raw link text with the expected source and, when
  that differs, their resolved real paths, so a link written through `/private/tmp` still counts
  as installed.
- Roots are injected (`userRoot`, `currentDirectory`) rather than read from
  `homeDirectoryForCurrentUser`, so unit tests, integration tests, and manual verification run
  against temporary homes and throwaway repositories; no test or verification step touched a
  live skill folder.
- `--path` requires `--scope project` (`INVALID_ARGUMENT`), mirroring `--prompt` requiring
  `--profile`. Missing/invalid roots reuse the existing `PATH_NOT_FOUND` /
  `PATH_NOT_DIRECTORY` codes; unexpected filesystem failures use `SKILLS_FAILED` following the
  `*_FAILED` convention. A bare `install` that detects no target fails with
  `TARGET_NOT_FOUND` instead of succeeding with nothing installed; a bare `uninstall` in the same
  situation succeeds with empty results.
- `list` reports user scope only; project-scope status is visible through the `install` /
  `uninstall` `before` field. Runtime reader labels for the `agents` target live in the
  contract and manual, not in the declarative target data.
- Not in K2: Settings Agent Skills section, `AgentSkillsFeature`, `SkillInstallClient`, copy
  mode, third-party skills, auto-install after updates, Git mutations, new targets.

## Review hardening

Adversarial review round 1 (sibling Pi agent, brief and findings kept outside the repository):

- Project-scope commands followed repository-controlled symlinks: a committed `.agents ->
  /elsewhere` link let `--scope project` write into (or remove links from) a folder outside the
  repository while reporting an in-repository path. `ProwlSkillInstaller.projectBoundaryViolation`
  now refuses a target whose parent or skills directory resolves outside the canonical root, the
  executor pre-checks every selected target before any change (`INSTALL_CONFLICT`), and the
  shared `install`/`uninstall` enforce the same rule so K3 cannot bypass it. User scope still
  follows symlinks on purpose. Symlinks that resolve inside the repository remain accepted.
- An explicit `--path` accepted any directory, including a non-repository or a nested folder
  that runtimes never read. Both spellings now resolve to the Git root containing the start
  point, and a start point outside a repository is `PATH_NOT_FOUND`.
- The `prowl-cli` skill line implied that all three user targets are always linked; it now says
  detected targets and points at `--target`. `INVALID_SKILL_FRONTMATTER` joined the manual's
  error table.

Round 2 found no P0/P1 and one P2: `installedDifferentSource` and `broken` dropped the link's
actual destination, so neither the CLI nor K3 could name the other source the plan promises for
Debug/Release switches. The shared status now carries `destination` (resolved against the link
directory; nil for a real file or directory), `list` exposes it as an optional `destination`
field and `→ path` in text, and the contract, schema, and manual document it.

Round 3 found the app test target no longer compiled after the status change (a hand-rolled
status closure in `CLIInstallClientTests`; it now delegates to `SymlinkInstaller.status`) — the
focused Xcode run before the round-2 commit had been read through a pipeline that hid
xcodebuild's exit code, so its "pass" was wrong — and that the schema accepted
`destination` on every status. `skillTargetStatus` is now a status-discriminated `oneOf`:
`destination` required for `broken`, optional for `installed_different_source`, forbidden
otherwise, with negative fixtures for each invalid combination.

Round 4 re-verified every earlier fix and reported no findings at any level; the review loop
closed there.

Real-environment verification on onevcat's Mac (owner-authorized, restored afterwards) found a
setup-specific defect the temp-directory tests had not modelled: `~/.claude/skills` and
`~/.codex/skills` are both symlinks to one synced folder, so the `claude` and `codex` targets
alias the same link. `uninstall` removed it for `claude`, then hit `notInstalled` for `codex`
and aborted with `SKILLS_FAILED`, leaving the `agents` link behind; `install` had relinked the
shared slot and reported `installed` twice. The executor now re-reads each slot right before
acting on it — an already-installed slot is left alone and an already-empty slot is skipped —
and the contract documents aliased targets. Pinned by an executor test with two targets
symlinked to one folder.

## Verification

- TDD RED: 116 missing-symbol errors across the five new CLI test files before the shared
  types existed; one hang exposed a `GitRootLocator` loop past `/` (`deletingLastPathComponent`
  of `/` yields `/..`), fixed by stopping at the filesystem root.
- `make build-cli` and `make test-cli-smoke` pass; the smoke target now also runs
  `skills list --json` against a temporary skills root and home with the socket unavailable.
  After the review rounds, `make test-cli-unit` passed 128 tests and `make test-cli-integration`
  passed 102. New coverage: 14 installer, 7 target, 22 executor, 5 parser, 4 schema, and 5
  integration tests;
  the integration tests run the real binary with an unavailable `PROWL_CLI_SOCKET`, a temporary
  `PROWL_SKILLS_DIR`, a temporary `HOME`, and a throwaway Git repository, and validate every
  JSON envelope against the schema bundle.
- App: `CLIInstallClientTests` (existing cases plus dangling-link status, live install repair,
  and live uninstall of a dangling link) and `SettingsFeatureCLIInstallTests` passed (18 tests
  in the focused run, re-run after the round-3 fix). `make test` on the fixed tree verified
  2,624 main app tests plus 2 isolated tests with zero failures; `make check` passed (strict
  formatting, SwiftLint, 44 script tests); `make build-app` passed and the Debug app contains
  `Contents/Resources/skills/prowl-cli/SKILL.md`, identical to the source file, and its bundled
  `prowl-cli/prowl` resolves the skills beside itself.
- Real environment (owner-authorized): with the Debug app's bundled `prowl-cli/prowl` and no
  overrides, `skills install prowl-cli` linked the skill into the synced `~/.claude/skills` /
  `~/.codex/skills` folder and a new `~/.agents/skills`; Codex 0.149.1 `skills/list` returned
  `prowl-cli` with the bundle path and `errors: []`, and Claude Code 2.1.247 `--debug` reported
  `user: 29` skills versus `user: 28` after removal — the differential proof that the linked
  skill was loaded. Everything was uninstalled and the folders restored to their baseline (the
  synced repository's working tree stayed clean).
- Manual: a temporary `Prowl.app/Contents/Resources` layout with the CLI symlinked from a
  temporary `bin/` on `PATH`; bare-name invocation resolved to the real executable
  (`BUNDLE_NOT_FOUND` names the resolved path); list → bare install (detected only) →
  explicit `--target codex` creation → workflow refusal → real-directory conflict with the
  conflict-free target untouched → project-scope install from a nested directory of a `git
  init` repo with the note once on stderr and `git status` showing only an untracked
  `.codex/` → JSON uninstall with zero stderr bytes → user-scope uninstall of all three
  targets. The live `~/.claude/skills`, `~/.codex/skills`, and `~/.agents/skills` were not
  read as inputs or modified.

## Refs

- Slice: 065-K2
- Branch: `feat/bundled-skills-k2`
- PR: #730
- Depends on: [003-k1-bundle-registry.md](003-k1-bundle-registry.md)
