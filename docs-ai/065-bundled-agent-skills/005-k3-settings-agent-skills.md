# 065.005 — Agent Skills Section on the Command Line Tool Page (K3)

## Context

K2 (#730) gave the `prowl` CLI status, install, and uninstall for every bundled skill × target
link, but a user who never opens a terminal still had no way to see that Prowl ships skills or
to link them. K3 is the last 065 slice: the Settings › Agents › Command Line Tool page gains an
**Agent Skills** section that exposes exactly the CLI's user-scope actions, backed by the same
shared installer so both surfaces always report the same status.

## Change

- `SkillInstallClient` (`supacode/Clients/SkillInstall/`) is the TCA dependency over the shared
  installer, shaped like `CLIInstallClient`: `bundledSkills()`, `status(skill, target)`,
  `install(skill, target)`, `uninstall(skill, target)`, `revealSkill(skill)`. `liveValue` reads
  `Bundle.main.resourceURL` and the user's home; `live(resourcesURL:userRoot:)` builds the same
  client over any roots so tests run against a temporary bundle and home, and `testValue` is an
  inert stub. `SymlinkInstallError` maps to `SkillInstallError.message` the way `CLIInstallError`
  does: a real file or directory is reported as occupying the slot and never deleted.
- `AgentSkillsFeature` (`supacode/Features/Settings/Reducer/`) is a child of `SettingsFeature`
  (`agentSkills: State?`), created when `SettingsFeature.setSelection` resolves to
  `.commandLineTool` and cleared on every other section (unlike `agentProfiles`, which
  `AppFeature` manages — see Review hardening for why). `.task` loads the
  `user`-audience skills and one `SkillLink` per **detected** target (`SkillTargetStatus.detected`);
  `installLink` covers Install, Repair, and Replace (all replace the slot with a link to this
  bundle), `removeLink` removes a symlink only, `revealSkillButtonTapped` opens the bundled
  folder in Finder. Every completion — success or failure — recomputes all rows and chips, because
  aliased targets (`~/.claude/skills` and `~/.codex/skills` symlinked to one folder) share one
  physical link. A failure sets an "Agent Skills Error" alert on the child and delegates a
  warning toast; a success delegates a success toast (`AppFeature` maps
  `agentSkills(.delegate(.linkChanged))` to `repositories.showToast`).
- `AgentSkillsSectionView` renders under Installation and Connection: one row per skill (name,
  id when it differs, the skill's `metadata.prowl-summary` — falling back to the agent-facing
  `description` — and Reveal), then one full-width line per detected target laid out as a
  `Grid` so the four columns align: status icon + target name, the link folder
  (`~`-abbreviated, monospaced, middle-truncated; a second line carries `→ destination` for a
  foreign or dangling link, or the "not a symlink" explanation), the status wording of
  `prowl skills list` (Installed / Not installed / Linked elsewhere / Real file or directory /
  Broken link), and one action button (Remove / Install / Replace / — / Repair). Empty states:
  the bundle could not be read (message from `ProwlSkillsError`), no installable skills, and no
  detected target (points at `prowl skills install --target claude|codex|agents`). Every button
  carries a tooltip; the folder cell's tooltip holds the full paths.
- `ProwlSkills` gained the optional `metadata.prowl-summary` field (`BundledSkill.summary`):
  a skill's `description` is agent-facing trigger text (`prowl-cli`'s runs to a paragraph of
  colloquial phrasings), so Settings shows the summary instead. Absent → nil; empty or duplicated
  → `INVALID_SKILL_FRONTMATTER`. The CLI payload and contract are unchanged.
- Docs: `docs/components/settings.md` gains an Agent Skills section (statuses, actions, aliased
  targets, empty states) and `docs/components/cli.md` notes that Settings offers the same
  user-scope actions with the same status as `prowl skills list`.

## Decisions and boundaries

- Success feedback is a toast plus the line's own state change; only failures raise a modal
  alert. The CLI-install row alerts on success as well, but a per-link modal for up to three
  chips per skill would be noise, and the toast path is the same `AppFeature` mechanism.
- Detection and status come from the client's `SkillTargetStatus`, so the reducer never reads
  the home directory itself and undetected targets are simply absent (the CLI's `--target`
  creates them). Workflow-audience skills are filtered in the reducer, not the client, because
  the audience rule belongs to this surface.
- Load and status refresh are synchronous in the reducer (a handful of `lstat` calls plus one
  frontmatter parse), matching the CLI-install row's synchronous `installationStatus`; only
  install/uninstall run as effects.
- Not in K3: project scope, copy mode, third-party skills, auto-linking after updates, new
  targets, changes to the shared installer or the CLI contract. `ProwlCLIShared` is untouched.

## Review hardening

Adversarial review round 1 (sibling reviewer, brief and findings kept outside the repository)
found no P0/P1 and one P2: the child state was created and cleared by `AppFeature.setSelection`,
the grandparent, whose core `Reduce` runs before the `Scope` into `SettingsFeature` — so the
nested optional was already nil when `SettingsFeature`'s `ifLet` ran, the `ifLet` never observed
a non-nil → nil transition of its own, and an in-flight install/uninstall effect survived the
section switch; its delayed completion then hit
nil child state (a TCA runtime warning in Debug) and was dropped without the promised refresh,
toast, or failure alert. The reviewer reproduced it with a suspended-install probe. The lifecycle
now lives in `SettingsFeature.setSelection` (create on `.commandLineTool` when absent, clear
otherwise), so `ifLet` cancels the child's effects with the state; `AppFeature` no longer touches
`agentSkills`. Pinned by an `AppFeature` test that suspends install/uninstall on a `TestClock`,
switches to General, and requires every effect to be gone.

Round 2 re-verified the fix (including re-selecting the same row, reopening Settings mid-action,
and creating a replacement child) and found no P0/P1/P2; its one P3 was that this record and the
action log had described the reducer order backwards ("after the `ifLet` had run"), corrected
above. The review loop closed there.

Owner feedback after the loop (2026-08-28): the agent-facing description was far too long for
the row and its hover tooltip misbehaved, and the content-sized capsules had unequal widths with
an empty gap before the buttons. The row now shows `prowl-summary`, and the per-target lines
became an aligned full-width `Grid` that also shows each link's folder (impeccable layout pass:
three equivalent targets are a table, not floating chips; no nested containers inside the
grouped Form card).

## Verification

- TDD RED: 25 missing-symbol errors for `SkillInstallClientTests` before the client existed;
  21 for the `AppFeature` selection and toast tests before the wiring existed. GREEN: 11 client
  tests (all four statuses, foreign-link destination, install/replace/repair, conflict refused
  with the directory intact, uninstall of links only, aliased targets) and 10 `TestStore` tests
  (`user`-only rows, detected-only chips, install/remove/repair/replace transitions with full
  refresh, aliased refresh, conflict alert, bundle missing, reveal, unknown ids ignored), all
  over temporary roots; the `AppFeature` selection tests cover `agentSkills` creation and
  clearing and the toast mapping.
- `make check` passed (strict swift-format, SwiftLint, 44 script tests); `make build-app`
  passed with zero warnings and the Debug app bundles `Contents/Resources/skills/prowl-cli/SKILL.md`
  identical to the source; `make build-cli`, `make test-cli-unit` (129) and
  `make test-cli-integration` (102) passed unchanged.
- `make test`: 2,643 main app tests passed; one deferred-Ghostty-surface test
  (`WorktreeTerminalStateAgentProfileTests/deferredProfileAppliesFontSizeAdjustmentAfterSurfaceCreation`)
  failed with `.surfaceCreationFailed` while the display was asleep (`pmset -g log`) and passed
  when re-run with the display awake; a full re-run under `caffeinate` passed 2,644 main app
  tests plus the 2 isolated shell-cancellation tests with zero failures.
- Visual: a copy of the Debug app launched with `CFFIXED_USER_HOME` (Foundation ignores a bare
  `HOME` override) and a dedicated `PROWL_CLI_SOCKET`, so its settings, home, and skill folders
  lived in a temporary directory. Screenshots of Settings › Agents › Command Line Tool show the
  section in every state: Not installed × 2 with `codex` undetected; Installed / Real file or
  directory / Broken link `→ /Volumes/Old/…` with Remove / no button / Repair; Linked elsewhere
  `→ …/DerivedData/…` with Replace; aliased `claude` + `codex` both Installed from one link; and
  the no-target explanation. The Mac was locked during the run, so button clicks could not be
  delivered to the isolated instance; the action path is covered by the `TestStore` tests over
  the live client. The live `~/.claude/skills`, `~/.codex/skills`, and `~/.agents` were neither
  read as inputs nor modified.

## Refs

- Slice: 065-K3
- Branch: `feat/bundled-skills-k3`
- PR: #731
- Depends on: [004-k2-skill-installer-cli.md](004-k2-skill-installer-cli.md)
