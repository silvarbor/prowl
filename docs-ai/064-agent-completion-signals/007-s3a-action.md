# 064.007 — S3a Claude/Codex Managed Hooks

## Status

Implemented on `feat/agent-signal-hooks-s3a-implementation`; implementation PR [#721](https://github.com/onevcat/Prowl/pull/721).
S3 wave 1 remains incomplete until S3b and S3c merge.

## Delivered behavior

- Claude Code and Codex adapters now declare only their approved S3a native-event capabilities.
- Profile launch preparation is asynchronous before dispatch issuance. The frozen target,
  inheritance cwd, runtime cwd, home, profile, and config overrides are revalidated before a
  synchronous surface/register/arm/bind transaction.
- Profile surface creation is genuinely two-phase: the exact view/surface identity is installed
  with Ghostty creation deferred, one evidence epoch and hook registration are established, then
  Ghostty is created with its native `initial_input`. Prompted dispatch binding adopts that epoch.
- Arbitrary argv values use typed child-only carriers. Settings JSON, notify overrides, token,
  socket, and forwarding locator never enter typed terminal input; the pane shell does not export
  the public hook token to later manual launches.
- Claude's final effective explicit `--settings` source is merged in memory with stable bounded
  reads. Unknown fields and existing hook arrays survive; Prowl handlers deduplicate; malformed,
  changed, unreadable, non-object, and oversized sources launch unchanged with one warning.
- Codex effective `notify` resolution uses its bounded official app-server initialize +
  `config/read` JSONL protocol. Base config, profile-v2 files, and final top-level CLI override are
  resolved without reading provider fields into logs or durable state. Project `notify` remains
  excluded by Codex itself.
- Existing Codex notifiers are preserved through random owner-only records and a hidden bundled
  CLI dispatcher. The bridge leases/reads before transport, keeps exact argv boundaries, scrubs
  internal environment, and `exec`s the notifier with the original payload even after listener
  loss. Trust revocation is immediate; retirement and orphan cleanup are lease-aware.
- The hidden `agents _hook` parser is absent from help/completion. Claude stdin and Codex final-argv
  payloads are bounded and normalized without `last_assistant_message`. The app accepts only an
  exact token/pane/runtime/event/cwd/generation registration and then exposes
  `hook_claude|hook_codex` as `verified_live`.
- Safe preparation failure never blocks the runtime: GUI launches show one warning toast; CLI
  success adds optional `warnings: [{code: "managed_hook_degraded", runtime, message}]`. JSON keeps
  it in stdout and text renders it exactly once to stderr.
- The Settings Launch Preview remains the deterministic base invocation. Conditional execution
  settings, tokens, socket paths, and forwarding locators are prepared only after live preflight
  and stay redacted. This is more honest than rendering a Codex override that may be omitted after
  notifier degradation; current docs now state that boundary explicitly.

## Phase 0 runtime evidence

Re-attested 2026-08-24:

- Claude Code `2.1.241`; Codex CLI `0.149.0`; Pi `0.84.2`.
- Claude repeated `--settings` is final-source-wins. A scratch authenticated run produced
  `SessionStart`, `Stop`, and `SessionEnd`; only the final settings handler fired. The observed Stop
  payload included `last_assistant_message`, which the bridge deliberately excludes.
- Codex app-server accepted initialize/initialized/`config/read` against scratch homes. Effective
  `notify` was `null` for a clean home, preserved exact Unicode/empty argv from base config, and
  reflected final `-c notify=...`. A trusted project layer loaded unrelated values but still
  excluded project `notify`.
- Codex profile-v2 is `$CODEX_HOME/<name>.config.toml`; app-server rejects `--profile`. Prowl
  therefore stable-reads only that file into an owner-only parser home and asks Codex to parse it
  as temporary user config.
- Contrary to the frozen plan's “last cwd wins” wording, 0.149.0 rejects repeated `-C/--cd`.
  Separate, joined (`-Cdir`), and equals forms are supported. Prowl autonomously chose the safe
  behavior: repeated cwd degrades managed hooks and preserves the original (runtime-rejected)
  launch rather than inventing an effective cwd.
- A real authenticated Codex notify run produced `agent-turn-complete` as the final argv with
  thread id, turn id, cwd, and last assistant message. Sanitized payload fixtures retain the
  shape while excluding real IDs/results.

All scratch probes guarded the live Claude/Codex config hashes. Runtime-added trust/state entries
were removed only when the current hash still matched the probe result, restoring the exact
pre-probe hashes.

## RED → GREEN record

Focused failing tests were observed before each logic layer existed:

1. native payload decoding, adapter capabilities, Claude settings merge, Codex notify rendering,
   and arbitrary argv carriers;
2. app-server JSONL parsing, notifier absence/presence/profile/override precedence, cwd/profile
   option parsing, malformed/recursive degradation;
3. forwarding record permissions, exact argv, shared-read/exclusive-cleanup leases, retirement,
   and orphan sweep;
4. pending early-hook activation, exact rejection matrix, verified coverage, session rotation,
   process replacement, and one-epoch dispatch adoption;
5. hidden CLI parsing, schema, kernel peer-PID socket routing, silent listener loss, exact notifier
   `exec`, environment scrub, warning omission/output channels, and preflight cancellation.

The first live Debug attempt exposed a real race not visible in pure tests: sending text immediately
after creating an unarmed surface could lose the command before the shell was ready. That approach
was removed. Regression coverage now asserts that the view/tree/profile identity is installed while
Ghostty creation is still unarmed, and that native `initial_input` is armed only after registration.

## Validation

Focused app suites: 100+ managed-hook/profile/CLI/lifecycle tests passing. The live Codex
`config/read` contract test passed against 0.149.0 with scratch absent/base/profile/override and
project-exclusion fixtures. CLI subprocess integration proved silent zero-exit listener loss and
exact notifier forwarding with empty/Unicode argv, unchanged payload, scrubbed internal variables,
and original notifier exit status.

Repository gates passed on the implementation branch: `make build-cli`, `make test-cli-smoke`,
`make test-cli-integration` (96 integration tests), `make check` (including 34 script tests),
`make test` (xcresult verified 2521 tests, zero failures), and `make build-app`. The enabled live
Codex 0.149 scratch contract also passed.

The full Debug GUI matrix was attempted with a freshly embedded bundle CLI, custom socket,
`CFFIXED_USER_HOME` scratch Prowl state, scratch workspace, owner-only Codex homes/auth copies, and
hash guards proving live Claude/Codex config restoration. The host GUI session was at `loginwindow`:
LaunchServices created the Debug process/socket but no visible main window, while direct launch had
no display and Ghostty reported `CVDisplayLink` invalid display count / surface initialization
failure. No shell/agent process could exist, so these GUI rows remain `INCONCLUSIVE`, not PASS. The
real framed socket/peer ancestry path, deferred pre-input registration ordering, hook decoding,
listener loss, notifier forwarding, and app composition are executable automated coverage; the
single-app visible-pane matrix remains a required manual/owner follow-up when a GUI session is
available.

## Adversarial review

### Round 1 — trust, launch transaction, epochs, and forwarding lifecycle

The first independent full-diff review blocked on five valid P1 findings. All were reproduced
against the current code and corrected with focused regression coverage:

- Codex preflight now resolves an absolute executable plus `HOME`/`CODEX_HOME` through the same
  non-logging login-shell environment a Profile command uses. An unprovable/non-absolute result
  degrades without injection; the app's launchd PATH/home can no longer authorize notifier
  replacement.
- Peer/task cancellation is checked after every preparation await, before and after forwarding
  record creation, and immediately before dispatch issuance. Capacity/failure/cancellation paths
  explicitly discard unexposed records; the cancellation test deliberately returns a successful
  preparation after observing cancellation and still proves no issue/launch.
- Managed-hook session identity is independent from detector hints. Detector `nil` cannot erase a
  verified session, and detector-first same-process replacement remains unverified until Claude
  sends the matching `SessionStart`.
- Deferred Ghostty arming now fails when `ghostty_surface_new` returns nil, resets its armed state,
  and rolls back the exact tab/split registration instead of reporting a launch with no process.
- Forwarding cleanup initializes an orphan sweep at app startup and owns a clock-driven retry loop
  until every retired record can take the exclusive lease; one busy first pass no longer leaves
  sensitive argv indefinitely.

The review also confirmed the peer-PID ancestry boundary, pre-input order, bounded early-event
buffer, exact cwd rejection (including memories), hidden bridge silence/deadline/`execvp`, payload
exclusion, carrier redaction, and owner/mode/no-follow/lease checks. Focused validation after the
fixes passed 89 tests plus `make check` (34 script tests).

### Round 2 — races, cancellation, argv rendering, and runtime compatibility

The second independent review accepted four additional P1 findings:

- Login-shell environment resolution had no hard deadline or streaming output cap. It now uses a
  purpose-built process runner with a one-second deadline, combined stdout/stderr bound,
  cancellation, TERM-to-KILL escalation, and tests for a noisy shell plus a TERM-ignoring hang.
- Frozen menu/palette target validation checked only anchor existence. It now tracks whether focus
  and cwd were inherited dynamically, re-reads both immediately after preflight, and retries or
  degrades rather than launching a stale context.
- Renderer fallback inferred any final argv after `exec`/`-p` as a prompt. Only the planner-owned
  prompt index can move insertion before a prompt now; arbitrary option/value argv remains exact.
- Stable settings/profile reads compared only the open descriptor. Claude and Codex now share one
  bounded owner-file reader that also `lstat`s the source path and compares device/inode/type,
  size, and mtime, so atomic replacement degrades safely.

A follow-up hardening discovered while verifying the first finding also carries an explicit Profile
`PATH` override into login-shell executable resolution; the prepared runtime invocation then uses
the attested absolute executable. Focused round-2 validation passed 77 tests plus `make check`.

### Round 3 — final full-diff blocker review

The final review reproduced two remaining boundedness failures with temporary-only probes:

- Opening a user-selected FIFO with read-only/no-follow flags blocked before type validation. The
  shared stable owner-file reader now adds `O_NONBLOCK | O_CLOEXEC`; a FIFO regression returns
  `.unreadable` within 200 ms without a writer.
- `SO_RCVTIMEO`/`SO_SNDTIMEO` were per-syscall rather than a total hook deadline. CLI transport now
  carries one monotonic deadline across write and both response reads, using `poll` with the
  remaining interval. A five-byte response dripped every 200 ms now exits silently within the
  bounded threshold, while existing listener-loss and Codex forwarding tests retain fail-open
  behavior.

Both were valid P1 findings and are fixed with focused tests. The final repository gate rerun after
round 3 verified 2521 app tests, 96 CLI integration tests, 34 script tests, strict format/lint, and
the Debug build; round-3 focused regressions also pass. No P0/P1/P2 code finding remains. The only
residual is the separately documented visible-GUI acceptance limitation.

## Post-merge review hardening

A 15-finding review arrived after PR #721 merged. Each finding was traced against the merged code and the
verified correctness paths were reproduced before correction. Ten logic/runtime regressions failed together in
the first focused RED run; two native failure paths were also reproduced independently with default signal and
kernel peer-credential probes.

The 12 verified correctness findings are fixed:

- the shell probe now drains stdout/stderr through EOF instead of spinning on `POLLHUP`, so successful Codex
  preflight completes normally;
- managed registrations survive transient generation lookup failure and a genuinely slow first process, Codex
  thread rotation rebinds the exact channel, and confirmed process replacement clears the prior session;
- outbound CLI sockets, accepted app-server sockets, and Codex app-server stdin suppress `SIGPIPE` at the
  descriptor level, preserving fail-open behavior without relying on Ghostty's process-wide signal policy;
- menu/palette split launches again fall back to a tab, while explicit CLI/workflow split requests remain strict;
- generated Claude/Codex options stay before an existing `--`, and Claude option scanning stops at that boundary;
- login-shell marker parsing tolerates unrelated profile output while still rejecting duplicate/incomplete facts;
- every live forwarding-store instance holds an owner lock for its session directory, so a second Debug/Release
  instance cannot sweep records that are merely old; crashed stores remain reclaimable;
- the socket accept loop freezes same-user PID ancestry before MainActor routing, and native hooks continue routing
  after their bounded client exits; ordinary long-running CLI requests retain disconnect cancellation;
- deferred Ghostty surfaces apply the `font_size_adjusted` no-op only after native creation, preserving inherited
  and preferred font sizes across config reloads.

The three cleanup findings were deliberately not expanded into this correctness patch: the two subprocess runners
still share only behavioral tests rather than a new abstraction, repeated evidence lookup remains bounded by entry
deduplication/title coalescing, and startup orphan maintenance remains synchronous and normally tiny. No measured
user impact justified broad lifecycle or concurrency refactors. The one-second shell deadline also remains: the
verified defect was strict whole-stdout parsing, while the local real login shell completed in under 10 ms and the
review supplied no slow-shell measurement. The deadline continues to fail soft with an explicit warning.

Focused RED → GREEN coverage now includes successful child EOF, shell banners, `--`, generation flaps and delayed
startup, Codex `/new`, process/session replacement, active cross-instance orphan ownership, split fallback, native
font initialization, default-`SIGPIPE` CLI execution, early app-server exit, and short-lived socket peers.

A follow-up disconnect-seam review found two additional lifetime gaps and one nondeterministic test. Accepted sockets
now receive `SO_NOSIGPIPE` and `FD_CLOEXEC` immediately after `accept`. The disconnect monitor atomically duplicates
its descriptor with `F_DUPFD_CLOEXEC`, monitors only that owned descriptor, and closes it from the DispatchSource
cancellation handler; `handleClient` remains the sole owner of the accepted descriptor and performs no synchronous
source wait. The regression tests coordinate accept, peer close, and MainActor routing with explicit semaphores, so
they prove the peer closed after identity capture but before routing. The owned-descriptor test failed against the
previous monitor and passes after duplication; the three disconnect-seam tests also passed ten repeated runs.

A second post-merge review exposed four additional asymmetric boundaries. The login-shell runner now stops waiting
for inherited pipe writers after the tracked shell exits, while still draining all immediately buffered output. The
launch option scanner stops at `--`, matching managed-option insertion. Codex thread rotation retains a per-process
set of retired session IDs, so detector-confirmed and hook-driven rotation accept a new thread without allowing a
late event to rebind an old one. Login-shell facts now end with an explicit marker and must form one ordered,
contiguous record, preserving unrelated profile output while rejecting multiline value truncation.

The same review hardened descriptor exhaustion and lifecycle handling: peer descriptor duplication happens before
routing and fails the connection closed with a warning, and the monitor activates its owned DispatchSource during
construction so no suspended source can reach deinitialization. Seven focused regressions failed against the prior
implementation and passed ten repeated runs after correction. The review's proposed narrowing of menu split fallback
was rejected because menu/palette compatibility intentionally retries any failed saved split as a tab; the user guide
now documents that behavior. A finite managed first-generation lifetime remains a separate design decision: restoring
the old ten-second cutoff would reintroduce the verified slow-start failure, while indefinite registration remains
constrained by token, runtime, CWD, event, and ancestry validation.

The descriptor-duplication regression initially used an unbounded client response read, which could stall the full
parallel test host under load. It now coordinates accept, peer close, and explicit rejection with semantic evidence.
The final serialized app suite passed 2549 tests in 40.8 seconds, and the default parallel suite completed without a
stall. Its only failures were the two pre-existing `ShellClientStreamingTests` cancellation timing flakes; both passed
immediately in an isolated two-test run. Static format/lint checks, the CLI build and 97-test integration suite, and
the Debug app build also passed. A final read-only adversarial review found no P0/P1 defects; its sole P2 corrected
user documentation that still described the first managed generation as subject to the old acquisition deadline.

## Follow-up: Codex 0.149.1 drops queued requests on stdin EOF (2026-08-25)

Upgrading Codex from 0.149.0 to 0.149.1 turned every Codex Profile launch into
`managed_hook_degraded` ("The effective Codex notifier could not be resolved"). Measured by hand
against the new binary: `codex app-server` answers `initialize`, then exits as soon as stdin
reaches EOF, and a `config/read` still queued at that moment is never answered — with stdin held
open for one more second the same three messages get the full reply. `CodexConfigReadProcess`
closed the request pipe immediately after writing, which 0.149.0 tolerated and 0.149.1 does not.

The pipe now stays open until the read loop has the `config/read` response (or the deadline);
the deferred `stop` then terminates the server and closes it. Covered by
`requestStdinStaysOpenUntilTheConfigReadResponseArrives()`, whose stub exits on EOF exactly like
0.149.1, and re-attested with `CodexConfigReadLiveContractTests` against the real 0.149.1
(`TEST_RUNNER_PROWL_RUN_LIVE_CODEX_CONTRACT=1` — the `TEST_RUNNER_` prefix is what carries the
variable into the test host). Live: a Codex Profile launch reaches `verified_live` with
`source=hook_codex` again, and the user's effective notifier (Codex's bundled computer-use client)
is preserved through the forwarding record.

## Deferred scope

S3b owns Copilot/Droid/Qoder adapters. S3c owns Pi/OMP/OpenCode adapters and the Active Agents exact
badge. Manual launches and those runtimes remain on existing cooperative/transcript/process/screen
evidence in this PR.
