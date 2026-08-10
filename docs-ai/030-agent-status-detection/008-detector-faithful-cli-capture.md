# 030.008 — Detector-Faithful CLI Capture Source

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-06 |
| **Primary PR** | [#684](https://github.com/onevcat/Prowl/pull/684) |
| **Plan** | [007-screen-profile-migration-plan.md](007-screen-profile-migration-plan.md), Phase 1 |
| **Related** | `docs/components/cli.md`, `docs/components/agent-detection.md` |

## Context

The production state detector reads `GHOSTTY_POINT_ACTIVE` through
`GhosttySurfaceBridge.readActiveText()`. Before this change, `prowl read` used
`GHOSTTY_POINT_VIEWPORT`; a scrolled pane could therefore produce a capture different
from the detector's actual input. A versioned fixture corpus built from that command
would have false provenance.

## Change

`prowl read` now accepts an explicit source:

```bash
prowl read --pane "$pane" --source detection --json
```

- `viewport` is the default and preserves all existing snapshot/scrollback behavior.
- `detection` reads `GhosttySurfaceView.readActiveContentsForCLI()`, the same method
  reached by production `readActiveText()`.
- The success payload reports `source: "detection"`; the CLI rejects a successful
  response that does not honor the requested source (for example, from an older running
  app), and fixture tooling must still verify the value before accepting text.
- Omitting `--last` returns the complete active buffer unchanged. `--last` remains a
  supported line projection but is not used for detector fixture capture.
- `--wait-stable` polls only the requested source. Normal reads do not pay for an extra
  Ghostty text read.

The read request source decodes to `viewport` when absent, preserving requests from an
older CLI. The app's capture provider carries the requested source explicitly and rejects
a mismatched provider result. The response schema remains `prowl.cli.read.v1`; the new
source value appears only when explicitly requested.

Raw screen content is returned only to the explicit `read` caller. It is not logged,
added to status payloads, or committed automatically. `.local/agent-screen-captures/` is
the canonical ignored private staging directory; CLI/component/skill documentation
requires source verification and redaction before a fixture is added.

## Validation

Test-first failures established the missing parser and handler contracts. After the
implementation:

- `CLIReadCommandHandlerTests`: 18 passed, including exact trailing-newline preservation,
  detection-only `--last`, mismatched-source rejection, and legacy request decoding.
- SwiftPM: 77 passed.
- CLI integration filter: 67 passed, including JSON/text stale-app rejection without
  returning viewport text.
- Full app suite: xcsift reported 2,272 passed; the xcresult backstop independently
  verified 2,275 tests and zero failures.
- `make test-cli-smoke`, `make build-cli`, `make test-cli-integration`, `make check`, and
  `make build-app` passed.

A second Debug app was launched against an isolated Unix socket and temporary plain
workspace. After printing 120 synthetic sentinel lines and scrolling its real Ghostty
viewport with an AppKit/CGEvent input path:

- default read returned `source: "screen"`;
- detection read returned `source: "detection"`;
- viewport and active-buffer SHA-256 values differed;
- the detection capture retained the newest sentinel while the scrolled viewport did not.

No raw user or agent content was used in this live verification.

## Result

Phase 1's exit condition is met: a live pane's exact detector input can be captured
reproducibly without a local patch or Debug-only app facility. Fixture loading,
provenance metadata, redaction policy enforcement, and fresh Claude/Codex captures remain
Phase 2 work.
