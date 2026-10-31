# 083 — TraeCode CLI (`traecli`) Support: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-10-12 |
| **Primary PRs** | (fill in as they merge) |
| **Related** | [077-antigravity-cli-support](../077-antigravity-cli-support/000-plan.md), [076-devin-cli-support](../076-devin-cli-support/000-plan.md) |

## Background

TraeCode CLI (`traecli`, verified 0.201.7, on-prem edition) is the standalone
terminal agent for the Trae IDE. Its binary is a Codex-CLI fork: it keeps Codex's
flag surface, `config.toml` model, session-store layout, and skill loader under
its own `~/.trae` home. Prowl detects and launches the other agent CLIs but has no
`traecli` integration, so a `traecli` pane reads as a plain shell.

## Goals

First-class `traecli` support at the same tier Antigravity landed in 077:

- Process detection (`traecli`, `traex` — the real executable — plus the
  `trae-cli`/`trae-agent` shims; **not** bare `trae`, which is the IDE launcher).
- Exact session ownership via the open
  `~/.trae/cli/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` rollout file (held
  open for the life of an interactive session), plus the Codex-shaped
  day-directory candidate roots and full-root fallback.
- Screen-state detection (legacy detector, bounded 24-line tail): a directory-trust
  dialog or a numbered choice dialog whose selection row is marked by a column-0
  `❯` is Blocked; an `esc to interrupt` hint is Working; the composer status row
  `<model> · Context <n>% left · <cwd> ▧ Workspace Edit` under a `❯` prompt row is
  Idle; anything else is Unknown.
- `AgentProfileRuntime` + `TraeRuntimeAdapter`: `--model`/`-m`; reasoning effort
  `-c model_reasoning_effort=low|medium|high|xhigh|max`; Standard / Unrestricted
  (`--dangerously-bypass-approvals-and-sandbox`, also spelled `-y` or
  `--permission-mode bypass_permissions`); prompted launch seeds the task as a
  trailing positional argument; headless launch uses `traecli exec <prompt>`.
- Account isolation through `TRAE_HOME` (relocates the whole `~/.trae` tree) with
  session root `cli`.
- `trae` + `traecli`/`traex` tab icons (bundled mark, Simple Icons CC0 asset).
- `trae` skill target (`~/.trae/skills` user, `.agents/skills` project — traecli's
  skill loader is Codex's) and CLI schema enums.
- Workflow token `trae` via the existing `DetectedAgent` rawValue set.
- docs/ + skills manual updates; focused tests in `TraeSupportTests`.

## Non-goals

- **Managed hook channel (`hook_trae`).** traecli supports JSON hooks and a
  `hooks`/`skills` config surface, but they live in the user's `~/.trae` config and
  this fork's managed-hook model deliberately writes no user config. Needs a
  product decision first; tracked as follow-up.
- **Typed `TraeScreenProfile` + fixture corpus.** Typed rules are obliged to carry
  `prowl read --source detection` captures (`AgentScreenRuleCoverageTests`), which
  require driving a Debug app against a live `traecli` pane. The exact working
  footer could not be captured live (the shared TraeCode app-server was serving
  this session's own TUI), so the working signature is the binary-verified
  `to interrupt` hint and the profile stays legacy for now.
- **`agents read` semantic reader.** The rollout JSONL exists but decoding stays a
  follow-up, same as the other runtimes.
- Bare `trae` binary classification — the Trae IDE ships a `trae` launcher that
  opens the desktop app.

## Design / Approach

Mirror 077's shape: `DetectedAgent.trae` (rawValue `trae`) forces the compiler
through `AgentProfileRuntime`, the adapter switch, `AgentSessionProfile`, and
`detectLegacyScreen`. The trae session profile is defined inline in
`AgentSessionProfile.swift` because it reuses the fileprivate `uuidJSONL`/
`dayDirectories` helpers. Edited: `AgentClassifier.swift` (`knownAgentBinaries` +
score-40 native-name rejection), `ScreenHeuristics.swift` (`detectTrae`),
`AgentRuntimeAdapter.swift` (`TraeRuntimeAdapter` + `accountIsolation`),
`CommandIconMap.swift` + `Trae.imageset`, `SkillInstallTarget.swift` +
`cli-output-schema.json` enums, `ProwlCommand.swift`, `SkillsCommand.swift`,
`make-detection-fixture.py` vocabulary, adapter/session/classifier/icon test
catalogs, docs, and skills.

Known lands on `make check`: the skill-target tests enumerate
`["claude","codex","agents","devin","antigravity"]` → append `trae`; the CLI
integration fixture gains a `.trae` directory alongside the others.

## Alternatives & decisions

- **`trae` as the token/case name, not `traecli`** — matches the product name;
  `traecli`/`traex` stay the binary/executable names. Bare `trae` is deliberately
  left unmapped at the classifier so an IDE launcher is never mistaken for the CLI.
- **Codex-shaped adapter over a bespoke parser** — traecli *is* a Codex fork, so
  reusing Codex's `--model`/`-c model_reasoning_effort`/bypass-flag spellings is
  the honest contract; Antigravity's Go-style flag parser does not apply.
- **Account isolation enabled (unlike Antigravity)** — `TRAE_HOME` was verified to
  relocate both config and `cli/sessions`, so a managed Profile home is honest.
- **Legacy detector over a typed profile** — the fixture-witness obligation cannot
  be met without a live Debug-app capture run against a real `traecli` pane.

## Open questions

- The precise live working footer (interrupt hint text and spinner glyph) once a
  standalone `traecli` TUI can be captured without the shared app-server.
- Whether the composer drops a paste-adjacent Enter the way Devin does; if
  `prowl send` drops delivery in acceptance, add `AgentComposerProfile` coverage.