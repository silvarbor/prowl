# 013 — Prowl CLI: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-30 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | contracts #89–#94, #97, #104; foundation #126, #127; runtimes #129, #133, #135, #136, #137, #141; install #146, #151, #153; growth #139, #148, #150, #157, #384, #405, #442 |
| **Sources** | `docs-ai/013-prowl-cli/contracts/architecture.md`, `doc-onevcat/plans/2026-04-04-cli-install-command.md`, `doc-onevcat/plans/2026-06-13-prowl-cli-agents-plan.md`, PR descriptions |
| **Related** | `docs-ai/013-prowl-cli/contracts/` (living normative spec), `docs/components/cli.md`, `skills/prowl-cli/SKILL.md`, [030-agent-status-detection](../030-agent-status-detection/000-plan.md) |

## Background

Prowl orchestrates multiple coding agents in parallel, each in its own worktree/tab/pane.
Both users and the agents themselves need a machine interface to a *running* GUI
instance: list worktrees/tabs/panes, focus a target, send text or key events, read a
pane's buffer, and open a path. An earlier shell prototype (`bin/prowl`) mixed argv
parsing with app behavior and drifted from what the app actually did. Issue #70 tracked
the redesign; the deliberate first step was to freeze machine-readable contracts before
writing any runtime code, so that CLI and app could evolve against one truth source.

## Goals

- A stable machine interface (`prowl`) for a running Prowl instance, with `--json`
  output an agent can script against (stable keys, stable `error.code` values,
  versioned schemas).
- Contract-first: the docs under `docs-ai/013-prowl-cli/contracts/` are the normative spec,
  locked before implementation; runtime work is validated against them.
- Parsing and validation live in a typed Swift CLI; command *execution* is app-owned,
  giving one authoritative runtime path for both GUI- and CLI-triggered actions.
- Reuse existing repository/terminal capabilities — the CLI is a transport + contract
  adapter, not a parallel runtime.

**Non-goals (phase 1)**: remote/multi-machine transport; a first-class "switch agent"
command (pane-oriented commands suffice); auto-prompting CLI install on first launch;
uninstall UI.

## Design / Approach

### Contract set (the normative spec)

The contracts are living documents — linked here, never duplicated. All of phase 1 was
specified before the first line of runtime code landed:

| Contract doc (`docs-ai/013-prowl-cli/contracts/`) | Defines | PR |
| --- | --- | --- |
| `open.md` | `prowl open` / bare-path output contract | #89 |
| `list.md` | `prowl list` output contract | #90 |
| `focus.md` | `prowl focus` output contract | #91 |
| `send.md` | `prowl send` output contract | #92 |
| `key.md` | `prowl key` output contract | #93 |
| `read.md` | `prowl read` output contract | #94 |
| `schema.md` | v1 JSON Schemas for all command outputs | #97 |
| `input.md` | Input contract: selector model, argv/stdin rules, token/repeat constraints | #104 |
| `architecture.md` | Phase-1 architecture + app interaction plan (absorbed below) | #104 |

### Architecture decisions (from `architecture.md`)

- **Decision A — first-class CLI binary**: `prowl` is a Swift executable built on
  ArgumentParser; the existing `bin/prowl` shell implementation is discarded. Parsing
  truth and input validation live in the Swift CLI module (typed request model, unit
  testability, no drift vs contracts).
- **Decision B — explicit command service boundary**: the CLI builds a normalized
  command request; the app resolves the target, executes, and returns a normalized
  response. The app never re-interprets argv-level ambiguity.
- **Decision C — execution is app-owned**: phase-1 commands are remote-control actions
  on running app state. `open` must be able to launch the app when it is not running.

### Module layout and protocol

| Layer | Planned components |
| --- | --- |
| CLI (`ProwlCLI` target) | ArgumentParser commands + validation; typed inputs (`OpenInput`/`ListInput`/…); transport client; output renderer (`--json` = raw contract payload, text = readable summary) |
| App (`CLICommandService`) | Command router mapping envelope → handler; one handler per command; shared `TargetResolver` and terminal/repository bridges |
| Shared types | `CommandEnvelope`, `Command`, `CommandResponse`, `TargetSelector`, input models, stable error codes, socket constants |

Transport: a single local IPC channel with a fixed API contract —
`request(CommandEnvelope) -> CommandResponse`. `architecture.md` deliberately left the
channel choice open; the v1 foundation (#126) fixed it as a **Unix domain socket**
carrying **length-prefixed JSON** (4-byte big-endian length + payload), one
request/response per connection, with app-not-running mapped to a stable
`APP_NOT_RUNNING` error code. Responses carry a versioned schema id
(`prowl.cli.<command>.v1`).

Target resolution is owned by the app (state-aware): the CLI only enforces selector
syntax and mutual exclusivity (`--worktree | --tab | --pane`); the app maps the selector
to a concrete worktree/tab/pane and echoes the resolved target in the output.

Milestones: M0 contract lock → M1 parser/runtime split (Swift target, shell discarded)
→ M2 command service scaffold (transport verified with stub handlers) → M3 phase-1
handlers with full error-code mapping → M4 tests and hardening (parser golden tests,
`--json` schema validation, `list → focus → send/key → read` integration loops).

### Install & distribution (absorbed from `doc-onevcat/plans/2026-04-04-cli-install-command.md`)

Once the runtime existed, users needed a way to get `prowl` onto their `PATH` without a
package manager:

- `CLIInstallClient` — a TCA dependency client handling symlink creation, status
  checking, and bundled-binary path resolution. Status model: `.notInstalled`,
  `.installed(path:)`, `.installedDifferentSource(path:)`.
- The CLI binary is embedded at `Prowl.app/Contents/Resources/prowl-cli/prowl`;
  installation symlinks `/usr/local/bin/prowl` to it.
- Three entry points — Settings › Advanced, the Prowl app menu, and the Command
  Palette — all funnel into a single `installCLI` action in `AppFeature`.
- Makefile gains CLI build/embed targets; the app bundle includes `Resources/prowl-cli/`.

## Alternatives & decisions

| Decision | Rejected alternative | Rationale (as recorded) |
| --- | --- | --- |
| Swift executable with typed parsing | Keep/extend the `bin/prowl` shell script | Strict typed requests, parser unit tests, deterministic behavior, lower drift vs contracts |
| Contract lock before runtime (M0) | Implementation-first, document later | Explicitly framed as preventing a repeat of parser-in-shell + CI churn before contract decisions were final |
| App-owned target resolution | CLI resolves selectors itself | Resolution is state-aware; CLI cannot see live app state, so it validates syntax only |
| `send --capture` via screen-buffer diff | Other capture approaches from #147 | "Approach A (Screen Buffer Diff)" chosen: snapshot before/after, diff, strip echo/prompt (#148) |
| CLI version generated from `MARKETING_VERSION` | Hand-maintained version string | Single version truth shared with the app; regenerated by the release flow (#151) |
| `prowl agents` is read-only, no switch subcommand | First-class agent-switching command | Automation resolves `pane.id` from `agents --json`, then uses existing `focus`/`read`/`send` (2026-06-13 plan) |

## Amendments

- Updated 2026-06-14: read-only `prowl agents` command exposing the Active Agents
  roster over the CLI — see [002-agents-command.md](002-agents-command.md)
- Updated 2026-08-22: CLI governance was rebaselined by 060 (#700), then extended through
  the same four-layer contract with deterministic `create pane` (#710), per-pane identity
  (#713), and typed Profile launch plus `profiles list` (#714). The living contracts under
  `contracts/` and `docs/components/cli.md` remain the current truth.
