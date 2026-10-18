# 082 — SSH Remote Agents: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-10-16 (revised 2026-10-17 after review rounds 1 and 2) |
| **Primary PRs** | #921 (this plan); implementation PRs per the slice table |
| **Related** | [002-spike-findings.md](002-spike-findings.md), [079-program-status-osc-7501](../079-program-status-osc-7501/000-plan.md), [068-agent-state-providers](../068-agent-state-providers/architecture.md), [064-agent-completion-signals](../064-agent-completion-signals/000-plan.md), [069-undo-close-terminal](../069-undo-close-terminal/000-plan.md), [067-remote-mirror](../067-remote-mirror/000-plan.md), `docs/components/agent-detection.md` |

## Background

Users ask for repositories that live on another machine: add the repository in the local
sidebar, start and switch agent sessions there, and let the agents, builds and tests run on
the remote host. Prowl cannot do this today. A closed attempt (#98) added SSH hosts, remote
repositories and tmux flows but did not land. An external proposal (WAMaker, fork branch
`feature/remote-agent-server`, also numbered 082 there) put a resident `prowl serve` daemon
with HTTP, token pairing, a custom PTY stream and protocol clients on the remote host.

Constraint set by onevcat: no forced hooks, no forced shell integration, and manual sessions
(`ssh host`, then start an agent by hand) must be covered, not only Prowl-launched ones.

Every stage of local detection depends on the local process probe: `AgentProcessProbe` reads
the pane's foreground process group with libproc (`ProcessDetection.swift`), and
`WorktreeTerminalState+AgentDetection.swift` runs nothing else when no agent is identified.
In a pane that runs `ssh`, the foreground process is `ssh`, so the pane has no agent. But the
screen bytes and OSC 7501 reports already reach the local Ghostty surface through SSH. The
real gaps are (1) remote process identity, (2) remote file evidence (session stores,
transcripts, pid registries), and (3) session survival when the local side disconnects.

## Goals

Three layers, delivered in order. Each adds user value when it lands, but they depend on
each other: L1 reuses the L0 connection layer, and L2 builds on the L1 folder model. L0 also
works in ordinary local-repository panes.

| Layer | Value | Remote requirement |
| --- | --- | --- |
| L0 — SSH-transparent detection | A manual `ssh host` + agent in any Prowl pane shows in Active Agents with live state and the host | None installed; correlation rides distribution-default `SendEnv`/`AcceptEnv LC_*` |
| L1 — Remote folders | Remote repositories and worktrees in the sidebar; tabs, splits, scripts and Profile launches open on the host | `git`, `/bin/bash`, `sh` |
| L2 — Persistent sessions | Remote panes attach to Prowl-managed tmux automatically; sessions survive tab close, app quit, Mac sleep and network loss | `tmux` (default on when present) |

### Non-goals

- L3, a resident remote observer (observation and notifications while Prowl is not
  running, sessions outside Prowl's tmux that no Prowl pane shows, remote file evidence).
  Decided 2026-10-16: not planned. If a need appears, it must be a stdio-only observer
  (`ssh host prowl serve --stdio`), never HTTP with pairing.
- A custom PTY stream protocol or a new terminal component. SSH is the PTY transport; the
  local terminal stays a Ghostty surface.
- Agent protocol clients (Codex app-server, ACP).
- Remote managed hooks and workflow participation from remote panes. The `ssh -R` socket
  channel works (002), but the remote side needs a Prowl CLI binary. Later work.
- Remote file-based evidence: session ids, transcripts, `agents read` results, Codex daemon
  child work.
- Exact identity for an agent that emits no OSC 7501 when no correlation channel exists.
- mosh, Eternal Terminal, nested ssh, `docker exec` chains, nested tmux.
- Remote diff window, workspaces, Finder, clone to remote.

## Design / Approach

### Shared contracts

These land first; later slices rely on them.

**C1 — Host identity.** Three separate things:

| Concept | Content | Use |
| --- | --- | --- |
| `HostProfile` | Persistent UUID, display alias, connection recipe (destination and supported options) | Persisted repositories, sessions, settings keys |
| `ConnectionKey` | Effective user, hostname, port, jump chain and config context, from `ssh -G` | Side-channel sharing, process scope, cache keys |
| Alias | What the user typed | Display only |

Editing the display alias never redirects a persisted repository; `-l alice` and `-l bob` on
one host are different connection keys. The private ControlPath is a short hash of the
connection key (below 104 bytes). A stored recipe still resolves through `~/.ssh/config`, so
Prowl re-resolves it with `ssh -G` before use. When the effective user, hostname or port no
longer matches the stored connection key (for example `HostName` was edited), Prowl pauses
every operation of that host profile and asks the user to rebind to the new target or keep
the old one (decided 2026-10-17).

**C2 — Typed process reference.** `ProcessRef` is `.local(pid)` or
`.remote(connectionKey, bootID, pid, startToken)`. It replaces naked pids in `ForegroundJob`,
`IdentifiedAgentProcess` (`AgentClassifier.swift`), `PaneAgentState` (including
`retainedSession`, which matches a bare pid today), `AgentProcessGeneration`
(`AgentSignal.swift`, which compares `pid` and `startedAt`), caches and signal evidence.
Functions that read local OS state take a local-only type, so a remote reference cannot
compile into them: `processGeneration`, `processIsLiveAncestor`, `AgentSessionResolver`
(fd scans, cwd and transcript scans, `AgentPidArtifacts.swift`, Codex `daemon.pid`),
`CodexLogProvider`, `ClaudeRuntimeProvider`, Profile config roots,
`WorktreeTerminalManager.currentAgentEvidence`, CLI caller attribution and the
`agents read` snapshot path in `ProwlApp.swift`. Remote cwd stays a typed remote path, never
a local file URL. Evidence follows the process that owns it:

- Session and provider evidence belong to the identified (engine) process and retire when
  its generation changes.
- Profile and hook launch context belong to the launch process and survive an engine
  replacement while the same launcher is live (today's behaviour, `AgentClassifier.swift`
  `launchProcessID`, covered by `PaneAgentStateTests`).
- An origin change (local ↔ remote, or a different connection key) retires both.

Local generation identity stays pid + start time, as today. The `ConnectionKey` value type
ships with S1 because the remote `ProcessRef` case refers to it; its resolution and the
networking land in S2.

**C3 — Remote snapshot.** Every probe result carries connection epoch, sequence number,
acquisition interval (local monotonic start and end), completeness, and outcome (`complete`,
`partial`, `failed`, `timedOut`). Rules:

- Presence counts each sequence once, not once per pane tick.
- Only complete, fresh snapshots prove absence: two consecutive ones without the process
  release it (about 2 s at the active cadence).
- No fresh snapshot for 10 s makes the observation stale: "status unavailable · last seen
  <time>", never Idle, Done or exit. A complete host scan in which a pane is unmapped proves
  nothing about that pane's agent.
- Stale or unavailable evidence cannot satisfy `agents wait --until exit|idle|blocked`,
  dispatch admission or workflow readiness. Today removing a roster entry satisfies exit
  (`AgentConditionEvidence.swift`) and an unknown state hides the entry; remote panes keep
  the entry with its last observation instead.
- A response that arrives after its subscription is retired (local `ssh` exited, pane
  closed) is dropped.

**C4 — Connection owner.** One actor per connection key owns the side channel
(`ssh -o ControlMaster=auto -o ControlPath=<hash> -o ControlPersist=<n> -o BatchMode=yes`,
using `~/.ssh/config`, keys and launchd's `SSH_AUTH_SOCK`). The side channel always overrides
session effects from the config: `ClearAllForwardings=yes`, no `RemoteCommand`, no
`RequestTTY`, no `LocalCommand`. Panes and folders subscribe; the owner runs at most one
probe at a time and publishes the latest snapshot. Scheduling: a request runs at once when
the lane is idle; requests that arrive while it is busy coalesce into one pending refresh
that always runs next, so continuous screen output neither floods the host nor postpones
the refresh forever. Limits: 5 s whole-command deadline for a probe, cancellation and process
reaping, 256 KiB probe output, 64 KiB capture per pane, jittered backoff. Detection and git
operations use separate lanes, so a stalled git command cannot delay detection. Networking
stays off the main actor.

**C5 — Structured commands.** Remote work is an executable, argv, cwd and environment,
converted to POSIX shell text at one quoting boundary. Explicit scripts are limited to the
probe and `wt` (`sh -s`, `bash -s` with the script on stdin) and to the user's own repository
scripts, which run as typed terminal input.

**C6 — Probe wire format.** The production probe emits framed records with escaped fields and
byte limits. The spike format in 002 is evidence, not a parser specification. Records carry
the boot id and a native start token (Linux: `/proc/sys/kernel/random/boot_id` and start
ticks; macOS: `kern.boottime` and `lstart`), elapsed time, cwd, the tmux mapping and
`pane_in_mode`, and capture text when requested.

### L0 — SSH-transparent detection

1. **Correlation.**
   - Primary key: each pane exports `LC_PROWL_PANE=<pane UUID>` next to `PROWL_PANE_ID`
     (`launchEnvironment` in `App/Sources/Infrastructure/Ghostty/GhosttySurfaceView.swift`).
     It rides `SendEnv`/`AcceptEnv LC_*`. These are distribution defaults (macOS client and
     server, Debian), not an OpenSSH guarantee.
   - Secondary key: the `SSH_CONNECTION` endpoints of the remote session, matched against the
     local TCP socket of the pane's own `ssh` process. Usable only when that `ssh` owns its
     socket (no ControlMaster client, no ProxyJump), the endpoints are compatible, and the
     match is unique. NAT can translate the source port, so translated, proxied or
     conflicting evidence leaves the pane `unmapped` or `ambiguous`. It never overrides a
     valid primary key. It ships disabled until a port-translating network case passes.
   - A key binds only to a current candidate on the same connection key. Anchor caches are
     scoped by connection epoch and anchor generation, not by pid.
   - Correlation state per pane: `correlated`, `ambiguous` (for example two ssh jobs in one pane
     with one UUID), `unmapped`, `probeUnavailable`, `unsupported`. Prowl never picks an
     arbitrary anchor.
2. **Trigger and argv.** A foreground `ssh` makes the pane a remote candidate. Prowl parses the
   local `ssh` argv with an explicit supported grammar and resolves it with `ssh -G`. The side
   channel never replays forwarding, session or command options (`-L`, `-R`, `-D`, `-N`, `-f`,
   `-t`, `-W`, `RemoteCommand`, `LocalForward` …). Unsupported argv gives `unsupported`.
3. **Probe.** The C6 script runs over the C4 owner. Anchor: a process with a tty whose parent is
   `sshd` or `sshd-session:`. Pane id source: Linux reads the anchor's environ; macOS hides the
   environment of platform binaries (the `/bin/zsh` login shell), so it reads the foreground
   members' environment.
4. **Identity.** Probe records become a `ForegroundJob` of remote `ProcessRef`s and go to the
   unchanged `AgentClassifier`, using argv (Claude's native binary has its version as `comm`).
5. **Generation and OSC fence.** Generation equality is `(connectionKey, bootID, pid,
   startToken)`, never recomputed from receive time. Records stay in the store unchanged; the
   fence decides which ones count:
   - First agent since the local `ssh` started: records that arrived after the `ssh` start
     count, so reports sent before the first probe are kept.
   - Replacement: records that arrived between the last snapshot that confirmed the
     predecessor and the first snapshot that confirms the successor are ambiguous. Root and
     child records from that interval do not count; state falls back to the screen. After
     the successor is confirmed, only records that arrive later count, and predecessor
     children never count again. Retirement time is not treated as the successor's start.
6. **State.** Without tmux: local screen rules and OSC 7501 through SSH. Inside any tmux (the
   user's own or Prowl's): capture text is the state source, because copy mode, choosers,
   splits and other clients break "local screen = agent screen", and tmux drops OSC 7501
   (002). A local screen change triggers an immediate capture to keep latency low.
7. **Cadence.** Subscription driven, through the C4 scheduling rule. Prowl requests a probe
   when a new foreground `ssh` appears, on input and screen-change wakes, and when an unbound
   pane receives OSC 7501. Steady cadence: 1 s while a remote agent is active, 2–5 s
   otherwise. Warm means the side channel is open; cold includes connection setup. Latency is
   measured from agent process start to roster publication.
8. **Release.** Two consecutive complete fresh snapshots without the process (C3), or local
   `ssh` exit, release the agent. This replaces the six-tick local miss count for remote
   origins. OSC `clear` withdraws OSC evidence; the agent stays and state
   falls back to the screen (as 079 does locally).
9. **Degraded OSC-only binding.** For `unmapped` and `probeUnavailable` panes, a verified
   producer's root record (`app` = claude-code, pi, omp) binds with origin
   `remoteUnprobed(local ssh generation)`. It is a remote execution origin: local-provider
   guards and admission checks treat it as remote. Prowl never invents a remote pid.
   Confidence is heuristic. OSC has no heartbeat, so a quiet healthy producer and a silent
   `kill -9` look the same: the observation becomes stale, and only `ssh` exit releases the
   binding. "Verified" means the producer's protocol behaviour was checked, not that a payload
   is authentic.
10. **UX.**
    - A persistent `user@host` label on remote panes, tabs and Active Agents rows.
    - Connection health separate from agent state ("Working · last seen 12 s ago", "Status
      unavailable"), with a reason-specific action (retry, accept host key, why unmapped).
    - A clear marker when ssh ends and the pane returns to a local shell.
    - `prowl agents --json` carries host, correlation state and freshness.
    - Update `docs/components/agent-detection.md` and `docs/components/cli.md`.
11. **Admission.** A pane whose agent has a remote origin, including a manual `ssh` from a local
    repository, cannot be a workflow participant or a dispatch target that needs a receipt. The
    refusal is a clear error at the admission point, not only in the UI.

### L1 — Remote folders

L1 first makes "where the repository lives" an explicit dimension with one value (local),
then adds the second value (remote). Feature code asks capabilities, never the location.

- **Location dimension.** `RepositoryLocation` is `.local(URL)` or
  `.remote(hostProfileID, canonicalPath)`, orthogonal to `Repository.Kind` (git/plain). The
  path is canonicalized on the host (`cd <p> && pwd -P`) and stored losslessly (spaces, `%`,
  `#`, Unicode). A `Worktree` shares its repository's host.
- **Compiler-enforced inventory.** `Repository.rootURL` and `Worktree.workingDirectory`
  (about 145 and 78 uses today) are replaced by `location` plus `localURL: URL?`, nil for a
  remote location. Each call site picks one: go through the host, sit behind a capability, or
  unwrap because it is local by construction (for example a path from `NSOpenPanel`).
- **Host boundary.** `RepositoryHost` exposes operations, not mechanisms. The local
  implementation keeps today's fast paths (direct reads of `.git/HEAD`, `index.lock` and the
  12-byte index header that sets watcher timing); the remote implementation uses batched C5
  commands. `observeChanges(_:)` is FSEvents locally and polling remotely. `GitClient` gets
  execution from the host, not from a global `ShellClient` and ad-hoc `GitClient()`
  instances.
- **Capabilities.** A static policy `resolve(kind:location:)` combined with cached facts gives
  `available` or `unavailable(reason)` per feature. Remote tool facts (git, bash, tmux) and
  local client facts (`gh`, used locally for PR status) are separate, so a host without `gh`
  does not lose PR status.
  Reachability (reachable, unreachable, unprobed) is runtime state and stays separate. Views
  disable controls with a tooltip from the reason; the command palette filters by it. The same
  check runs at the execution and admission boundary, so a hidden button is not the only
  guard.

| Class | Features |
| --- | --- |
| Host-agnostic | Worktree list/create (copy flags)/remove/rename, branch and dirty state, GitHub PR status (resolve `owner/repo` once on the host, keep `gh` local with `--repo`), scripts and terminals |
| Local by nature | Finder, workspaces (`ProjectWorkspace`), external diff tool, clone destination |
| Deferred | Diff window (`git diff` + file read), line counts, icon detection; open in editor through remote URIs (`vscode://vscode-remote/ssh-remote+<host>/<path>`, Zed `ssh://`) |

Callers that bypass `ShellClient` today (clone, `ExternalDiffSnapshotClient`,
`DiffWindowState`, `OutgoingChangesClient`, workspace runner, archive script) move behind the
host or sit behind a capability.

- **Persistence and migration.** `PersistedRepositoryEntry` gains an optional host profile.
  Path-keyed `@Shared` stores, snapshots and the repository settings key
  (`~/.prowl/repo/<name>`) include the host profile; existing local identities migrate
  unchanged. The snapshot cache does not drop remote entries because of `fileExists`.
  Renaming or removing a host profile or a repository states what happens to its sessions.
- **Add flow.** "Add Remote Folder…" takes a host and a path; validation runs on the side
  channel. An unreachable host stays listed as unavailable.
- **Refresh.** One polling command returns HEAD, branch, porcelain status and the worktree
  list.
- **Terminals.** Tabs, splits and run scripts start through `ssh -t` with the stored
  connection recipe, typed as initial input so the pane falls back to a local shell (with the
  L0 marker) when ssh exits. A split inherits the remote cwd from the probe. The layout
  snapshot stores the origin so restore reconnects.
- **Profile launches.** Compiled from the structured invocation (argv, environment, remote
  cwd), not by rewriting `AgentProfileLaunchPlan.terminalInput`, which contains local home
  assignments and carrier references. Carrier values stay private (never visible in typed
  text) and payloads arrive byte for byte. Profiles that need a local dedicated home are
  unavailable for remote folders until remote account binding is designed. Managed hooks and
  Codex shell probes are skipped; L0 detection covers the session.

### L2 — Persistent sessions

The session belongs to the remote tmux; a Prowl pane is a window onto it. The user never runs
tmux by hand for this.

- **Option.** "Keep sessions alive (tmux)" per remote folder, with a global default in
  Settings. When the folder is added, the side channel checks for tmux through a login shell:
  present → on by default; absent → off, with a hint to install tmux.
- **Session per pane.** Each Ghostty leaf has its own managed session, keyed by a durable
  remote-session UUID stored in the snapshot leaf (`TerminalLayoutSnapshotPayload`). Tab and
  group identity are metadata. Prowl keeps a remote session apart from its zero or more local
  attachments.
- **Tags.** tmux user options record schema version, remote-session UUID, host profile UUID,
  canonical worktree path and local tab metadata. Discovery from another Mac matches the
  canonical path, not a local alias.
- **Create, attach, end are separate operations.**
  - Create: `new-session -d` with the tags in the same command chain, then attach. A Profile
    or script command is the session's initial command and runs only at creation.
  - Attach: `attach-session` to an existing session; restore never runs the initial command
    again. A missing session offers "Start new session" explicitly, so an ended session is not
    silently recreated.
  - End: `kill-session` on "End Session", ⌥-close, or worktree removal. It invalidates restore
    and undo entries.
  - Untagged or half-created `prowl` sessions are reconciled without rerunning a command.
- **Lifecycle (decided 2026-10-17).** Closing a pane or tab detaches; the session keeps
  running, and a notice says "Session kept running on <host>" with Undo. The remote tmux
  client detaches at close (over the side channel), so no hidden client keeps the session
  size or attachment count. Undo keeps a reconnect descriptor instead of the local surface
  mechanism of 069, and reattaches. App quit and connection loss also detach. No time-based
  cleanup.
- **Worktree remove and archive.** The confirmation names the host and lists the sessions
  that will end, with their agents. Then: validate (dirty check), end sessions, remove.
  Report partial outcomes. A lost connection is never reported as a successful end;
  reconcile before retrying a destructive step.
- **Discovery and visibility.** The remote tmux is the source of truth; the snapshot is an
  index. Opening a worktree lists its tagged sessions, so a lost snapshot or a second Mac
  reattaches instead of duplicating. The worktree row shows "N background sessions". The probe
  enumerates `tmux -L prowl list-panes -a` (no client needed) for identity and captures pane
  text for state, while Prowl runs and the folder is visible.
- **State and history.** Capture text is the state source for attached and detached sessions
  (L0 item 6). `prowl read --last N` on a managed session runs `capture-pane -p -J -S -N` on
  the exact pane id: stdout only (no tmux buffer), the last N lines of history plus the
  visible screen, wrapped lines joined, trailing blank lines removed, at most 64 KiB counted
  from the end. When the pane is in its alternate screen, the result is the alternate screen
  only and says so.
- **Launch command.** `ssh -t <recipe> 'cd <path> && exec "$SHELL" -lc "exec tmux -L prowl -f
  /dev/null …"'`; the login shell gives the tmux PATH. Options include `status off` and
  `focus-events on`; mouse, extended keys and history are decided during implementation.
- **Known limits.** No OSC 7501 inside tmux; the alternate screen leaves Ghostty scrollback
  empty; mouse and copy mode follow tmux; several clients on one session share one size.

### Follow-up UX items

Planned after the layer that enables them; not acceptance gates of that layer.

| Item | After |
| --- | --- |
| Host diagnostics page: SSH authentication, pane correlation, required tools, persistence availability, each with its own fix | L1 |
| Open in editor through remote URIs | L1 |
| Unified session picker: attached and background sessions with agent, worktree, last observation, attachment count, Resume, End Session | L2 |
| Reconnect to the same sessions after sleep or network recovery, keeping titles and layout; disclose another attached client before taking over | L2 |

### Slices and PRs

Contracts land before new behaviour, so launch and persistence are not rewritten later.
Exposure gates: S3 stays behind a flag until S4 ships its UX; persistent sessions (L2a) never
ship without the remove/archive safeguards. The secondary port key stays off until its NAT
case passes.

| PR | Slice | Content | Behaviour change |
| --- | --- | --- | --- |
| 1 | S1 | C2 typed `ProcessRef` and the `ConnectionKey` value type through classifier, pane state, generation, caches; ownership-based retirement (engine vs launcher); local-only OS entry points | None |
| 2 | S2 | C1 host identity, C4 connection owner, C3 snapshot contract, C5 command model, C6 probe and its parser (unit tested with recorded output) | None (unused) |
| 3 | S3 | L0 manual correlation: `LC_PROWL_PANE`, argv grammar, effective-config overrides, correlation states, generation and fence, release, stale projection, degraded OSC binding, admission refusal | Behind a feature flag |
| 4 | S4 | L0 UX: host label, connection health, ssh-ended marker, CLI fields, docs; turns the S3 flag on | Manual remote agents appear |
| 5 | S5 | L0 tmux: user-owned tmux mapping and capture-based state | tmux panes detected |
| 6 | L1a | `RepositoryLocation`, `localURL: URL?`, call-site triage | None |
| 7 | L1b | `RepositoryHost` local implementation (fast paths kept); `GitClient` routed through it | None |
| 8 | L1c | Capability policy with reasons, enforced at execution and admission | None for local |
| 9 | L1d | Remote host implementation, `HostProfile` persistence and migration, add flow, polling | Remote folders appear |
| 10 | L1e | Remote terminals, splits, scripts, layout restore | Remote tabs |
| 11 | L2a | Session model: per-leaf session UUID, tags, create/attach/end, detach at close with notice and Undo, capture state, history read, worktree remove/archive confirmation and ordering | Persistent sessions |
| 12 | L2b | Discovery, background sessions on the worktree row | Background sessions |
| 13 | L1f | Remote Profile launches from structured invocation (create-once inside L2 sessions) | Remote Profiles |

### Acceptance criteria (draft)

| Id | Criterion |
| --- | --- |
| L0-1 | Manual `ssh` + Claude Code or Codex appears with correct agent and host, measured from agent process start to roster publication: p95 ≤ 1.5 s on a warm connection, ≤ 3 s cold; on a macOS host and Linux hosts with `sshd-session` (OpenSSH ≥ 9.8) and `sshd` naming |
| L0-2 | Without tmux, Claude Code state follows OSC 7501 with local latency; Codex follows screen rules; Blocked shows for a permission prompt on both |
| L0-3 | Correlation matrix (`-F`, missing `SendEnv`/`AcceptEnv`, existing ControlMaster, ProxyJump, NAT port translation, conflicting primary and secondary keys, different users and ports, two ssh jobs with one UUID, `LocalForward`/`RemoteCommand` in config): correct attribution or an explicit degraded state, never an arbitrary match; the side channel opens no forwarding and runs no config command |
| L0-4 | `kill -9` of a probed agent releases within 3 s (two fresh snapshots); local `ssh` exit releases at once; OSC `clear` with a live process keeps the agent; late replies after `ssh` exit do not resurrect it |
| L0-5 | Jittered elapsed samples keep one generation; rapid same-agent restart; engine change under a live launcher keeps the launch context; predecessor child records and early successor reports follow the fence rules; local/remote pid collision; host A→B and remote→local in one surface; two hosts sharing a pid: zero local session, file or provider access for remote origins |
| L0-6 | Blackholed traffic, stopped side channel, hung probe, sleep/wake: "status unavailable" within 10 s; stale evidence never satisfies exit, idle, blocked, dispatch or readiness; no false Idle, Done or exit; bounded tasks and retries |
| L0-7 | User-owned tmux: identity via the mapping, state via capture; copy mode, pane switches and several clients do not misattribute; sustained screen output keeps at most one probe in flight and still refreshes; unmatched screens stay unknown |
| L0-8 | Unprobed or unmapped pane: verified producers show with heuristic confidence and remote origin; others show the correlation state |
| L0-9 | Cost against a recorded baseline: local CPU grows by at most 2 % of one core per 10 remote panes (measured at 1/10/50), plus remote CPU, bytes/s and subprocess count recorded; one in-flight probe per connection; probe p95 < 0.5 s on a host with ≥ 500 processes |
| L0-10 | No Prowl-installed files, configuration or probe artifacts on the host; no rc edits |
| L0-11 | Host label, connection health and the ssh-ended marker are visible; `prowl agents --json` carries host, correlation state and freshness |
| L1-1 | Add, persist, restore a remote folder; a display-alias edit does not redirect it; a changed `HostName` pauses operations until the user rebinds or keeps the old target; hostile but valid path characters work; an unreachable host stays listed |
| L1-2 | Old local settings and snapshots migrate unchanged; identical local and remote paths do not collide |
| L1-3 | Worktree list/create/remove/rename on a bash 3.2 (macOS) host and a bash 5 (Linux) host |
| L1-4 | Branch and dirty state refresh within one polling interval |
| L1-5 | Tab, split and run script open at the remote path; splits inherit the remote cwd; restore reconnects |
| L1-6 | Unavailable features are refused at the execution boundary (tests) and disabled with a reason in the UI; PR status works on a host without `gh` |
| L1-7 | L1a–L1c change nothing for local repositories: existing tests pass and local fast paths (watcher timing) are unchanged |
| L1-8 | Remote Profiles: large multiline prompts, empty arguments, quotes, `$`, `$(…)` text and environment overrides arrive byte for byte; carrier values never appear in typed text; dedicated-home Profiles are unavailable with a reason; reconnect never relaunches |
| L2-1 | Opening a remote worktree with the option on attaches tmux automatically; the user types no tmux command |
| L2-2 | A session survives tab close, app quit, network loss and sleep; restore reattaches with the screen intact |
| L2-3 | Two splits in one tab keep independent sessions through close, undo and restore |
| L2-4 | Close detaches the remote client at once, with a notice and Undo (reattach); End Session and ⌥-close end; an ended session is not recreated on restore; offline End Session is not reported as success |
| L2-5 | Lost snapshot or a second Mac: tagged sessions are found and reattached without duplicates; an interrupted creation is reconciled; no prompt or script replays on attach |
| L2-6 | Worktree remove/archive names the host and the sessions and agents that will end, validates before ending them, and reports partial outcomes |
| L2-7 | Background sessions show on the worktree row with agent identity and state |
| L2-8 | State via capture inside Prowl tmux, including copy mode and pane switches; `prowl read --last N` follows the history contract (line semantics, alternate screen, 64 KiB) |
| L2-9 | `docs/` documents the option, the detach semantics and the tmux limits |

## Alternatives & decisions

| Option | Decision |
| --- | --- |
| Resident `prowl serve` with HTTP, pairing and a PTY stream (external 082 proposal) | Rejected: daemon, linger and hook injection are more intrusive than hooks; manual non-tmux sessions get presence only; large scope |
| OSC `app` as the only identity | Rejected as the main path: 3 of 17 agents, no `kill -9` detection, self-declared. Kept as the degraded binding |
| `SSH_CONNECTION` client port as the only key | Rejected (breaks with ControlMaster and ProxyJump); kept as the secondary key (2026-10-17) |
| Preamble that reports the remote tty via OSC | Rejected: needs a Prowl-built command, misses manual `ssh` |
| Compiled remote probe binary | Rejected: a piped `sh` script works on macOS and Linux with no install |
| Read env of the anchor shell on macOS | Not possible (platform binary); read foreground members instead |
| Map tmux by inherited env | Rejected: the tmux server keeps the first client's variables; map by client tty |
| Generation from `localNow − elapsed` | Rejected (review round 1): unstable across samples and admits predecessors; use boot id + native start token, and an attachment-epoch fence |
| Alias in repository identity | Rejected (review round 1): alias edits redirect data; use `HostProfile` UUID |
| Local screen as state source inside tmux | Rejected (2026-10-17): copy mode, choosers and pane switches break it; capture everywhere in tmux, woken by local screen changes |
| Session per tab | Rejected (review round 1): splits would share a session; one session per pane |
| `new-session -A` for restore | Rejected (review round 1): recreates ended sessions; separate create and attach |
| Rewriting rendered `terminalInput` for remote | Rejected (review round 1): leaks carriers, keeps local home paths; compile from structured invocation |
| Commands only, no file reads, for local too | Rejected (review round 1): slows local paths; keep local fast paths behind the host boundary |
| Closing a remote tmux tab kills the session | Rejected (2026-10-17): against tmux's model and the "leave the agent running" use |
| tmux opt-in only | Rejected: default on when the host has tmux, because losing the agent on disconnect is the larger cost |
| Retire all pane evidence on any generation change | Rejected (review round 2): breaks launch context across engine replacement; evidence follows its owning process |
| Fence at the predecessor's retirement time | Rejected (review round 2): drops early successor reports and leaves predecessor children; ambiguous interval falls back to the screen |
| Filter argv only for the side channel | Rejected (review round 2): config forwarding and commands still apply; override them explicitly |
| Keep the tmux client attached during Undo | Rejected (review round 2): a hidden client changes session size and counts; detach at close, Undo reattaches |
| L3 resident observer | Not planned (2026-10-16) |

## Open questions

- Secondary key: reading the local `ssh` socket endpoints with libproc and the remote
  `SSH_CONNECTION` from a macOS foreground member; NAT and `ProxyCommand` behaviour.
- Real network loss (half-open TCP) and `ServerAliveInterval` for the side channel.
- Older `sshd` naming, Alpine and hardened `AcceptEnv` defaults.
- Probe cost on process-heavy macOS hosts (the spike calls `ps` per process).
- tmux option set: mouse, extended keys (Shift+Enter in agents), history limit.

## Amendments

- Updated 2026-10-16: spike record for L0–L2 — see [002-spike-findings.md](002-spike-findings.md)
- Updated 2026-10-17: revised in place after review round 1 — shared contracts C1–C6 (host identity, typed process reference, snapshot freshness, connection owner, structured commands, probe wire format), secondary port key, attachment-epoch fence, `clear` as withdrawal, capture-based tmux state, per-pane sessions with separate create/attach/end, structured remote Profile launch, local fast paths behind the host boundary, admission enforcement, UX items, PR order
- Updated 2026-10-17: revised in place after review round 2 — ownership-based evidence retirement and `ConnectionKey` in S1, replacement-interval OSC fence, effective-config overrides and authority rebinding, qualified secondary key, stale projection and remote-unprobed origin, scheduling rule and numeric budgets, detach at close with reconnect Undo, removal disclosure, exposure gates
