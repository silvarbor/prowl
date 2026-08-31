# 060 — Prowl CLI Targeting and Contract Governance: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-16 |
| **Primary PRs** | #700 |
| **Related** | [013 — Prowl CLI](../013-prowl-cli/000-plan.md), [046 — CLI Short Handles](../046-cli-short-handles/000-plan.md), [047 — Cross-Agent Handoff](../047-cross-agent-handoff/000-plan.md), [059 — Agent Transcript Snapshots](../059-agent-transcript-snapshots/000-plan.md), [#699 — CLI split-pane creation](https://github.com/onevcat/Prowl/issues/699), [`docs/components/cli.md`](../../docs/components/cli.md) |

## Background

Prowl's local CLI began with UUID-oriented, app-side target resolution. The original
contract goals were one grammar for humans and agents, typed parsing, a stable JSON
surface, and no hidden selector precedence. The implementation retains those useful
foundations, but capability growth split the public targeting language:

- `--pane <uuid|pN|N>` and `--tab <uuid|tN|N>` accept short handles.
- `--target` and positional auto-targets accept only pane/tab UUIDs or worktree
  id/name/path; `pN` and `tN` are not recognized there.
- `prowl agents read <pN|pane-uuid>` intentionally accepts a positional `pN` so a
  caller can directly consume text `prowl agents` output, but accepts no selector flags.
- `send` and `key` also overload positional argument count: one argument is payload for
  the focused pane, while two arguments make the first an auto-target.

Consequently, a user can run `prowl agents read p12`, but must write
`prowl read --pane p12`; `prowl read p12` does not resolve the pane. Worse, a generic
`p12` is still eligible to match a worktree named `p12`. This is an avoidable mismatch
between the handle Prowl displays and the target syntax users naturally try.

This entry governs the target-language correction and the contract/documentation
rebaseline required to keep it correct as the CLI expands. It does not itself change
runtime behavior. Until implementation lands, the shipped binary and
`docs/components/cli.md` describe current behavior.

## Current State

### Command surface

The current binary exposes these executable forms:

| Area | Forms | Target behavior |
| --- | --- | --- |
| Entry and discovery | `prowl [path]`, `prowl open [path]`, `prowl list`, `prowl agents` | `open` consumes a path; discovery commands are global. |
| Pane interaction | `focus`, `read`, `send`, `key` | Shared selectors; selected forms also accept an auto-target position. |
| Semantic agent inspection | `agents read <pN|pane-uuid>` | Required explicit agent pane; no focus/worktree/tab fallback. |
| Terminal lifecycle | `tab create`, `tab close`, `pane close` | Shared selectors; close requires one explicit selector. |
| Handoff | `handoff save`, `handoff to <agent>` | Shared selectors or an auto-target positional source; absent selector means the calling pane, not UI focus. |

`--json` and `--no-color` are common leaf-command output options. `send` adds
`--no-enter`, `--no-wait`, `--capture`, and `--timeout`; `key` adds `--repeat`; `read`
adds snapshot/stability options; close adds `--force`; and handoff adds briefing and
launch options.

### Current shared selector model

| Form | Current accepted values |
| --- | --- |
| `--pane` | pane UUID, `pN`, bare `N` |
| `--tab` | tab UUID, `tN`, bare `N` |
| `--worktree` | worktree id, name, or path |
| `-t` / `--target` | pane UUID, tab UUID, or worktree id/name/path |
| Existing positional auto-targets | pane UUID, tab UUID, or worktree id/name/path |

Selectors are mutually exclusive. The current implementation rejects a positional target
combined with any selector flag. This is stricter than older contract text that said a
flag would override the positional value.

No-selector behavior is intentionally command-specific:

- `focus`, `read`, `send`, `key`, and `tab create` resolve the current UI focus.
- `tab close` and `pane close` reject an omitted selector.
- `handoff` resolves the pane that spawned the CLI process; it never guesses UI focus.
- `agents read` requires an explicit agent pane.

### How the inconsistency arose

1. **013 — v1 CLI** established `TargetSelector`, typed CLI parsing, app-owned
   resolution, UUID JSON identity, and positional/flag auto-targets.
2. **Auto-target follow-up** added target-first forms such as
   `prowl send <uuid> "text"` and `prowl read <uuid>`.
3. **046 — short handles** correctly preserved UUID JSON identity and made handles
   process-scoped and non-reusable. To preserve a worktree named with a bare number,
   it restricted *both* bare numeric handles and prefixed `pN`/`tN` to `--pane` and
   `--tab`.
4. **059 — agent snapshots** deliberately made `agents read <pN|uuid>` a narrow,
   immediate semantic-inspection command. This was locally ergonomic, but made the
   global discrepancy visible.
5. **047 handoff hardening** changed selector-plus-positional parsing from precedence to
   rejection for target isolation. The code and tests changed, but the older input
   contract still describes precedence in several places.

The important correction is not to abandon short handles or UUIDs. It is to distinguish
an unambiguous prefixed handle from an ambiguous bare number.

## Goals

- Give every command that accepts a **generic target** one shared, documented target
  language.
- Make `pN` and `tN` work wherever the existing generic auto-target language works:
  `--target`, target-first positional forms, and future generic-target commands.
- Preserve UUIDs as the stable JSON and scripting identity; short handles remain
  process-scoped interaction shorthand.
- Preserve the safety reasons for command-specific exceptions: explicit agent inspection,
  explicit close, and caller-pane handoff source resolution.
- Re-establish a complete, current, testable contract set covering the actual command
  surface and make the user manual, CLI help, and agent skill agree.
- Make terminal lifecycle action-first: `create tab`, future `create pane`, and `close`.
  The existing `tab` and `pane` command groups become explicitly deprecated compatibility
  aliases rather than the vocabulary for new automation.
- Establish an ownership and verification workflow so later CLI growth cannot introduce
  another undocumented grammar fork.

### Non-goals

- Replacing UUIDs in JSON with handles, persisting handles, or making them valid across
  a Prowl restart.
- Adding a selector query language, title-based targeting, remote transport, streaming
  reads, or a new agent-control namespace.
- Changing `agents read` from an immediate semantic snapshot into a generic terminal
  reader.
- Changing handoff's caller-pane source rule or weakening explicit-close protections.
- Implementing split-pane creation itself. Its action-first public shape and contract
  boundary are owned by [#699](https://github.com/onevcat/Prowl/issues/699); this work
  establishes the parent `create` grammar it will extend.
- Broadening this work into terminal layout, agent-session, or worktree lifecycle
  redesign.

## Proposed Targeting Model

### One lexical target reference language

For every existing or future generic auto-target position, define:

```text
GenericTarget ::= PaneUUID | TabUUID | PaneHandle | TabHandle | WorktreeRef
PaneHandle    ::= "p" PositiveInteger
TabHandle     ::= "t" PositiveInteger
WorktreeRef   ::= worktree id | name | path
```

Resolution is type-directed for prefixed handles, then preserves the current UUID and
worktree behavior:

1. `pN` resolves only as a pane handle.
2. `tN` resolves only as a tab handle.
3. A UUID tries pane, then tab.
4. Any other value resolves as a worktree id, name, or path.

A bare `N` is deliberately **not** a generic handle. It remains eligible as a worktree
reference, while typed flags retain their existing convenience:

```text
--pane <uuid|pN|N>
--tab  <uuid|tN|N>
```

The recommended compatibility policy is to reserve valid `pN` and `tN` spellings for
handles in generic contexts. A stale `pN` must fail as a stale pane handle; it must not
silently act on a worktree named `pN`. A worktree with such a name remains addressable
unambiguously as `--worktree p12`. This is a narrowly scoped behavior change that
prevents stale interactive handles from retargeting a command.

### Command grammar after the correction

The existing command shapes stay intact; only their `GenericTarget` slots expand:

```bash
prowl focus p12
prowl read p12 --last 120
prowl send p12 'git status --short'
prowl key p12 enter
printf '%s\n' 'git status --short' | prowl send --target p12
prowl handoff save p12 --brief -
prowl agents read p12
```

`prowl send p12` remains text input to the focused pane because `send` still lacks a
payload target/value boundary with one positional argument. The correct target-first
form is `prowl send p12 'text'`; stdin callers use `--target p12` or `--pane p12`.
This is an inherent and documentable arity rule, not a target-resolution exception.

`agents read` continues to accept a required pane-only positional argument and no
selector flags. It shares the same `PaneHandle` lexical definition, but remains a
semantic agent command rather than a generic terminal read.

### Lifecycle operations use an action-first grammar

Terminal lifecycle operations are part of the same orchestration language as `read`,
`send`, and `focus`; they are not namespaces mirroring app implementation types. Their
new public forms are:

```bash
prowl create tab MyApp --path /path/inside/MyApp
prowl create pane p12 --direction right      # owned by #699, not implemented here
prowl close t6 --force
prowl close p12
```

The resource noun gives each action a typed target grammar:

```text
CreateTabTarget  ::= WorktreeRef
CreatePaneTarget ::= PaneUUID | PaneHandle
CloseTarget      ::= PaneUUID | TabUUID | PaneHandle | TabHandle
```

`create tab` accepts exactly one worktree reference, positionally or as `--worktree`.
`create pane` accepts exactly one pane reference, positionally or as `--pane`, and
requires an explicit direction. `close` accepts exactly one tab or pane reference,
positionally or with `--tab` / `--pane`; it accepts neither `--worktree` nor `--target`.
A positional target and a selector flag remain mutually exclusive. Thus `pN` and `tN`
route `close` without a selector projection rule, while a UUID resolves as a pane or tab.
All close forms remain explicit and retain `--force` for protected panes.

The former resource-first forms are deprecated compatibility aliases:

```bash
prowl tab create ...
prowl tab close ...
prowl pane close ...
```

They must be marked deprecated in help and emit a stderr migration warning on every
invocation without corrupting `--json` stdout. During one shipped-release compatibility
window, aliases retain their existing parser and selector behavior, including legacy
cross-resource projection, so existing automation does not silently change effect.
New contracts, documentation, examples, and automation must use the action-first forms;
the aliases may be removed after that window.

## Contract and Documentation Governance

The current `docs-ai/013-prowl-cli/contracts/` directory is a living normative contract
set, but it no longer covers the whole shipped CLI or all current fields. This work must
rebaseline it in the same implementation change as the runtime behavior.

### Contract set to reconcile

1. Add a shared `targeting.md` contract that owns target syntax, handle lifetime,
   resolution order, no-target semantics, selector exclusivity, and the distinction
   between typed and generic references. Command contracts must link to it rather than
   duplicate target rules.
2. Reduce `input.md` to root command parsing and per-command argv/stdin arity. Correct
   its selector-plus-positional rule to match runtime rejection; define `create tab` and
   `close`; and document deprecated `tab` / `pane` aliases, `handoff`, and `agents read`.
3. Update existing output contracts for shipped behavior:
   - `send.md`: document `--capture` and its incompatible combinations.
   - `read.md`: document `detection`, stable waiting, and all returned metadata.
   - `focus.md`, `key.md`, `list.md`, and `open.md`: reconcile fields, identifiers, and
     current error behavior against implementation tests.
4. Add contracts and schema coverage for commands that currently have only implementation
   and user-manual coverage: `agents`, `create`, `close`, deprecated `tab` / `pane`, and
   `handoff`. Keep the existing dedicated `agents-read.md` contract.
5. Update `schema.md` to enumerate every supported JSON wire response and either validate
   them in automated tests or explicitly narrow its status to a historical subset. The
   preferred outcome is complete executable schema validation.
6. Update `docs/components/cli.md` as the concise current user reference and
   `.agents/skills/prowl-cli/SKILL.md` as the safety-oriented automation guide. Both must
   use the shared target language and distinguish current-process handles from UUIDs.
7. Correct help text inconsistencies, including the `prowl agents --help` synopsis that
   currently implies a required subcommand despite `prowl agents` being valid.

### Durable ownership rule

- `ProwlCLI` ArgumentParser declarations are the executable source for command spelling
  and option inventory.
- `contracts/targeting.md` and command contracts are the normative public semantic source.
- `docs/components/cli.md` is the human-oriented reference derived from those contracts.
- The `prowl-cli` skill is an opinionated safety guide, never an independent behavior
  specification.

A new command or public flag is incomplete until all four layers have been updated and
validated together.

## Implementation Plan

### Phase 0 — Record the aligned public policy

Record the confirmed prefixed-handle reservation, action-first lifecycle grammar,
deprecation policy, and focused-pane fallback boundary in the shared contract before
changing parser or resolver behavior.

### Phase 1 — Centralize generic handle resolution

- Extend `TargetResolver.resolveAuto` to recognize `pN` and `tN` before UUID/worktree
  resolution, using the same handle validation as typed pane/tab selectors.
- Keep typed `--pane` / `--tab` behavior unchanged, including their bare-number support.
- Keep app-side target resolution; the CLI parser continues to transport a normalized
  `TargetSelector` without inspecting live state.
- Ensure a stale prefixed handle returns a typed target-not-found error and cannot fall
  through to a worktree selector.

### Phase 2 — Migrate lifecycle commands without breaking aliases

- Introduce top-level `create` and `close` parser groups. `create tab` owns a worktree-only
  target; `close` owns a pane-or-tab-only target. Reserve `create pane` for #699 rather
  than exposing an incomplete command.
- Add typed lifecycle selector parsing so the new commands reject `--target`,
  `--worktree` for close, cross-resource selectors, and worktree-like positional values
  before transport. Keep generic UUID resolution only where a UUID is valid for the
  action's resource type.
- Add versioned `create` and `close` wire inputs, responses, output rendering, schemas,
  and handlers. Preserve the existing `tab` and `pane` wire commands and response shapes
  for deprecated aliases, so their JSON output remains byte-compatible in the window.
- Mark `tab` and `pane` deprecated in generated help and write a single migration warning
  to stderr at invocation. The warning must name the precise replacement and never enter
  JSON stdout.
- Make the new commands delegate to shared lifecycle operation logic rather than creating
  a second set of close/create side effects.

### Phase 3 — Prove command parity and safety

Add parser, resolver, handler, and socket integration coverage for the target matrix:

| Form | Expected target interpretation |
| --- | --- |
| `read p12`, `focus p12` | pane `p12` |
| `send p12 'text'`, `key p12 enter` | pane `p12` |
| `send --target p12` with stdin | pane `p12` |
| `handoff save p12` / `handoff to codex p12` | source pane `p12` |
| `agents read p12` | semantic snapshot of pane `p12` |
| `create tab MyApp` / `create tab --worktree MyApp` | a new tab in that worktree |
| `close p12`, `close t6` | close the typed pane or tab, respectively |
| `close --pane p12`, `close --tab t6` | equivalent typed-selector close forms |
| `--pane 12`, `--tab 12` | existing typed bare-handle behavior |
| generic `12` | worktree behavior, never an inferred handle |
| stale `p12` / `t12` | target-not-found, never a worktree fallback |
| positional target + selector flag | `INVALID_ARGUMENT` |

Maintain tests for explicit close, legacy alias warnings and byte-compatible alias
behavior, and handoff's caller-pane fallback. The new action-first lifecycle commands
must reject cross-resource selectors before transport.

### Phase 4 — Rebaseline contracts, manuals, and help

Land all contract changes listed above with the runtime change, update examples to use both
UUID-safe automation and short same-session handoffs, replace lifecycle examples with
`create tab` / `close`, document the legacy aliases and their removal policy, and add a
checked command synopsis or help snapshot so option changes are mechanically visible in
review.

### Phase 5 — Validate the release surface

- Run focused Swift Testing suites for target resolution, command parsing, command handlers,
  and CLI integration.
- Run `make build-cli`, `make test-cli-smoke`, and `make test-cli-integration`.
- Run `make check`, `make test`, and `make build-app`.
- Manually verify one isolated Prowl session: text `list` → `pN` → generic read/send/key,
  JSON `list` → UUID automation, stale-handle failure, and explicit close behavior.
- Record actual outcomes in `001-action.md` after implementation.

## Risks and Compatibility

| Risk | Mitigation |
| --- | --- |
| Existing worktree named `p12` or `t6` changes generic auto-target behavior | Reserve prefixed forms; document `--worktree` as the unambiguous spelling and include release notes. |
| A stale handle silently reaches a different target | Do not fall back from prefixed handles; fail explicitly. |
| New CLI talks to an older running app | Resolver lives app-side, so retain the established transport/version failure guidance and ship CLI with the matching app. |
| Documentation re-drifts after this correction | Single target contract, help snapshot/check, and a four-layer completion rule for public CLI changes. |
| A generic `close` weakens destructive-command safety | Require one explicit typed tab/pane target; reject worktree, UI-focus fallback, and cross-resource selector projection. |
| Existing lifecycle scripts break during grammar correction | Keep `tab` / `pane` aliases byte-compatible for one shipped release, mark them deprecated in help, and emit stderr migration warnings. |

## Confirmed Public Decisions

1. **Prefixed handles:** `pN` and `tN` are reserved typed handles in every generic target
   context. A stale handle fails and never falls through to a same-named worktree.
2. **Lifecycle grammar:** new lifecycle commands are action-first: `create tab`, future
   `create pane`, and `close <pane-or-tab>`. The resource noun constrains selector type;
   new commands reject cross-resource selectors.
3. **Destructive targeting:** `close` always requires an explicit tab or pane target.
   Positional handles/UUIDs and typed `--tab` / `--pane` are equally explicit; worktree
   and UI-focus fallback are not accepted.
4. **Deprecated resource groups:** `tab` / `pane` are one-release compatibility aliases,
   visibly deprecated and warning on stderr. They preserve legacy behavior during that
   window, then may be removed.
5. **Focused-target defaults:** retain current convenience for non-destructive terminal
   operations. `handoff` continues to default to the calling pane, not UI focus.
6. **Contract enforcement:** every wire command has a complete versioned JSON Schema and
   automated validation against actual socket responses.
7. **Pane creation:** do not mix the runtime feature into this change. [#699](https://github.com/onevcat/Prowl/issues/699)
   owns `prowl create pane <pane> --direction <direction>`.

## Definition of Done

The work is complete only when a user can learn one target grammar and accurately predict:

```bash
prowl agents read p12
prowl read p12
prowl send p12 'status'
prowl key p12 enter
prowl focus p12
```

All five address the same live pane; `create tab` and `close pN` / `close tN` follow the
same action-first language; UUID JSON workflows remain stable; explicit close and handoff
safety rules remain deliberate exceptions; every command and flag has one current contract;
and tests make future divergence visible before release.
