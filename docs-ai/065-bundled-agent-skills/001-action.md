# 065 — Bundled Agent Skills: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-22 | Plan reviewed and accepted: bundle Prowl's own skills, direct bundle symlinks, skill × target granularity, `prowl skills`, Agent Skills section on the Command Line Tool page. | #712, [000-plan.md](000-plan.md) |
| 2026-08-27 | S0 verified the `claude` / `codex` / `agents` targets against installed runtimes in temporary homes: directory symlinks are followed, dangling links do not block discovery, copy mode stays deferred. | [002-s0-skill-targets.md](002-s0-skill-targets.md) |
| 2026-08-27 | K1 merged: `embed-skills` staging, `Resources/skills` folder reference, Foundation-only `ProwlSkills` registry with the frontmatter parser and `metadata.prowl-install` audience, CLI bundle resolution, typed errors. | #729, [003-k1-bundle-registry.md](003-k1-bundle-registry.md) |
| 2026-08-27 | K2 merged after four review rounds and an owner-authorized real-environment check: shared `SymlinkInstaller` (extracted from `CLIInstallClient`, adds `broken`), declarative `SkillInstallTarget`, `ProwlSkillInstaller`, local-only `prowl skills list\|install\|uninstall\|path` with contract, schema, manual, and skill line; aliased targets handled by re-reading each slot. | #730, [004-k2-skill-installer-cli.md](004-k2-skill-installer-cli.md) |
| 2026-08-28 | K3: `SkillInstallClient`, `AgentSkillsFeature`, and the Agent Skills section on Settings › Agents › Command Line Tool; `settings.md` / `cli.md` updated; 065 complete. | #731, [005-k3-settings-agent-skills.md](005-k3-settings-agent-skills.md) |
| 2026-08-29 | Shipped in v2026.8.29. The hosting page was renamed from Command Line Tool to **CLI & Skills**; the records above keep the name they were written under. | #735 |

## Outcome & current state (as of 2026-08-28)

- **Bundle.** `make build-app` / `test` / `archive` stage `skills/` into `Resources/skills/`
  (ignored, `rsync --delete`), which the Xcode project embeds as a folder reference, so the
  shipped app carries `Contents/Resources/skills/<id>/SKILL.md`. Today the only bundled skill is
  `prowl-cli` (`user` audience); 063's D1–D3 skills join by being added to `skills/` with the right
  `metadata.prowl-install`.
- **Registry.** `ProwlSkills` (`supacode/CLIService/Shared/ProwlSkills.swift`, part of
  `ProwlCLIShared` and compiled into the app) parses `name`, plain or `>-` `description`, and the
  strictly nested `metadata.prowl-install` audience and optional `metadata.prowl-summary`
  display text; `bundled(resourcesURL:)` serves the app,
  `bundledForCLI(executableURL:environment:)` resolves the CLI's own bundle or `PROWL_SKILLS_DIR`,
  and `skill(id:)` is the locator 063 uses.
- **Installer.** `SymlinkInstaller` (`SymlinkInstaller.swift`) owns one link slot with the
  statuses `notInstalled` / `installed(path:)` / `installedDifferentSource(path:destination:)` /
  `broken(path:destination:)`; it replaces live or dangling symlinks, refuses real files and
  directories, and removes symlinks only. `CLIInstallClient` delegates to it for
  `/usr/local/bin/prowl`. `SkillInstallTarget.all` (`SkillInstallTarget.swift`) declares
  `claude`, `codex`, and `agents` with user and project directories and the parent-exists
  detection rule; `ProwlSkillInstaller` composes skill × target × scope into a slot and enforces
  the project-boundary rule.
- **CLI.** `prowl skills` (`ProwlCLI/Skills/`) is local-only, contract `prowl.cli.skills.v1`
  (`docs-ai/013-prowl-cli/contracts/skills.md`, `cli-output-schema.json`,
  `docs/components/cli.md`, one line in `skills/prowl-cli/SKILL.md`).
- **Settings.** `SkillInstallClient` (`supacode/Clients/SkillInstall/`), `AgentSkillsFeature`
  (`supacode/Features/Settings/Reducer/`), and `AgentSkillsSectionView` (`.../Views/`) add the
  Agent Skills section to `CommandLineToolSettingsView`. `SettingsFeature.setSelection` creates
  the child state for `.commandLineTool` and clears it otherwise (so `ifLet` cancels in-flight
  link effects); every action recomputes all chips; results surface as toasts and failures as an
  alert. `docs/components/settings.md` documents the section.
- **Tests.** Registry, installer, target, executor, parser, schema, and integration tests under
  `ProwlCLITests/` (temporary roots, `PROWL_SKILLS_DIR`, temporary `HOME`); `CLIInstallClientTests`,
  `SkillInstallClientTests`, `AgentSkillsFeatureTests`, `AppFeatureSettingsSelectionTests`, and
  `AppFeatureAgentSkillsTests` under `supacodeTests/` (temporary bundle and home via
  `SkillInstallFixture`). No test reads or writes `~/.claude`, `~/.codex`, or `~/.agents`.

## Deviations from plan

- `SkillInstallTarget` has no `runtimes` field and `projectDirectory` is not optional: the
  reader labels for `agents` live in the contract and manual rather than in code, and all three
  targets have a project directory.
- `installedDifferentSource` and `broken` carry a `destination` (added in K2's review round 2)
  so the CLI and Settings can name the other build or the vanished location.
- The CLI re-reads each slot immediately before acting on it (K2 real-environment fix for
  aliased `~/.claude/skills` / `~/.codex/skills`), and Settings recomputes every chip after each
  action for the same reason; neither was in the plan.
- Project scope follows repository-controlled symlinks only inside the repository
  (`INSTALL_CONFLICT` otherwise), an explicit `--path` resolves to its Git root, and a bare
  `install` with no detected target fails with `TARGET_NOT_FOUND` — all K2 review additions.
- Settings reports a successful link with a toast only (the chip changes state); the plan's
  "mirroring the CLI install row" did not decide this, and a modal per link would be noise.
- `agentSkills` is created and cleared by `SettingsFeature.setSelection`, not by
  `AppFeature.setSelection` as the plan's `agentProfiles` analogy implied: the grandparent's
  `Reduce` runs before the `Scope` into `SettingsFeature`, so its mutation lies outside the
  child `ifLet`'s transition boundary and cannot cancel in-flight link effects (K3 review
  round 1, wording corrected in round 2).
- The section shows detected targets only, as planned, but the "no target detected" state adds an
  explicit pointer to `prowl skills install --target …` since Settings never creates folders.

## Open questions

- Copy mode (`--copy`) remains deferred until a supported runtime demonstrably refuses directory
  symlinks.
- Whether 063-D1's Workflows "ask your agent" prompt should run `prowl skills install` first.
- Settings UI for project scope (per-repository section) — V2 if asked.
