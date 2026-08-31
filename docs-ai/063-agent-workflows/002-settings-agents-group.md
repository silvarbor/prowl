# 063.002 — Settings Agents Group (C0)

## Context

Release R1 starts by establishing the Settings information architecture that later workflow UI will extend. The existing Agent Profiles page was a standalone “Agents” sidebar item, while the `prowl` installation controls lived under Advanced.

## Change

- Settings now reads: flat items (General … Commands, Advanced last) → `Agents` group (`Profiles`, `Command Line Tool`) → `Repositories` group.
- The profile list keeps the sidebar label `Profiles` and is titled `Agent Profiles`; `openAgentProfilesSettings` and “Manage Agent Profiles…” continue to select it.
- The Command Line Tool page owns the existing install/status controls and shows the Unix socket path `prowl` uses to reach the app (`ProwlSocket.defaultPath`, honouring `PROWL_CLI_SOCKET`). The copy describes where `prowl` connects; it does not claim the socket is live.
- Advanced keeps analytics, crash reporting, and terminal-layout controls, now split into `Analytics & Crash Reports` and `Terminal Layout` sections.
- The Workflows page remains absent until 063-D1, as planned.

## Deviations from plan

- The plan listed an “Ask your agent” entry on the Command Line Tool page. The existing Ask-Agent-About-Prowl prompt (Help menu, sidebar footer) is a user-onboarding prompt, not a CLI one, so it was not duplicated here. What this page should eventually carry is agent *skill* distribution — bundling the official skills (`skills/prowl-cli`, later workflow skills) into the app, a `prowl skills` CLI that links them into user or project skill folders, and an **Agent Skills** section on this very page mirroring the install row. That is [065-bundled-agent-skills](../065-bundled-agent-skills/000-plan.md) (#712); until its K3 lands the page has no agent-help section.
- Slice records in 063 are amendments starting at `002`; `001-action.md` is written when the entry completes (see `docs-ai/README.md`).

## Current state

The selection boundary is `SettingsSection.profiles` / `.commandLineTool` (`supacode/Features/Settings/Views/SettingsSection.swift`). Profile editor state is initialized only for the Profiles page and cleared when another page is selected (`AppFeature.swift`, `.settings(.setSelection)`). CLI installation behavior remains owned by `SettingsFeature`; C0 only moves its presentation to `supacode/Features/Settings/Views/CommandLineToolSettingsView.swift`.

## Deferred

- Socket listening status: a `CLISocketServer` start failure is only logged (`supacode/App/supacodeApp.swift`), so the page cannot tell “should listen here” from “is listening”. Surfacing `listening / failed(reason)` needs the server state plumbed into `SettingsFeature`; its natural home is the 063-D1 CLI preflight, which needs the same reachability signal.
- Skill distribution (`prowl skills` + the Agent Skills section here): [065-bundled-agent-skills](../065-bundled-agent-skills/000-plan.md), K3.

## Verification

- `make check` passed.
- Focused suites (`AppFeatureSettingsSelectionTests`, `AppFeatureCLIInstallTests`, `SettingsFeatureTests`, `CLIInstallClientTests`) passed; the test build also compiles the app target.
- `make test` on the initial revision: 2,366 verified, zero failures (five pre-existing dependency-scan warnings).
- An isolated Debug app was navigated through Settings to Profiles and Command Line Tool on the initial revision; both rendered with the expected native window titles and ordering.

## Refs

- Slice: 063-C0
- Branch: `feat/settings-agents-group`
- PR: #709
