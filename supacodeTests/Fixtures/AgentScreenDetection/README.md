# Agent Screen Detection Fixture Corpus

This directory contains sanitized, capture-derived inputs for the production screen
classifier. It is a regression suite, not a transcript archive and not a replacement for
focused inline predicate tests.

## Layout

Normal fixture:

```text
<runtime>/<cli-version>/<expected-state>/<scenario>.txt
<runtime>/<cli-version>/<expected-state>/<scenario>.metadata.json
```

Known current misdetection:

```text
<runtime>/<cli-version>/known-misdetection/<expected-state>/<current-state>/<issue>-<scenario>.txt
<runtime>/<cli-version>/known-misdetection/<expected-state>/<current-state>/<issue>-<scenario>.metadata.json
```

The harness accepts every `DetectedAgent`; the initial corpus contains only `claude` and
`codex`. States are `working`, `blocked`, `idle`, or `unknown`; `done` is display state
derived from `idle + unseen` and is never a fixture state.

## Capture and promotion

1. Run a current Debug build of Prowl and the matching bundled `prowl` CLI.
2. Capture the exact production input with `prowl read --source detection --json`.
3. Require `.data.source == "detection"`; never substitute a viewport read.
4. Keep the raw response under the ignored `.local/agent-screen-captures/` directory.
5. Record exact CLI version, capture timestamp, terminal rows/columns, and the redaction
   summary in a same-basename metadata file.
6. Reduce the capture with the production `agentDetectionRecentText` helper: start at
   the 24th non-empty line from the bottom when at least 24 exist; otherwise retain the
   whole screen. Keep blank lines and trailing screen rows inside that window.
7. Redact paths, repositories, account identifiers, and all real-session prompts/model
   output without changing runtime chrome, line ordering, markers, wrapping, or blank-line
   boundaries. Deliberately scripted probe interactions from disposable workspaces may
   remain verbatim and are preferred for conversational fixtures.
8. Run `AgentScreenFixtureCorpusTests` before committing.

The loader resolves this tree through `#filePath`, so tests intentionally run from a
source checkout rather than relying on test-bundle resource flattening.

Required metadata shape:

```json
{
  "schema_version": 1,
  "captured_at": "2026-08-06T12:34:56Z",
  "cli_version": "0.146.1",
  "capture_source": "prowl-read-detection",
  "terminal": {
    "columns": 120,
    "rows": 40
  },
  "redactions": [
    "working directory replaced with <WORKSPACE>",
    "user prompt replaced with <USER_PROMPT>"
  ],
  "issue": null
}
```

`issue` is required and non-null only in `known-misdetection`.

## Quarantine

A fresh capture that the current detector misclassifies must not be omitted or made into a
failing infrastructure PR. Put it under `known-misdetection`, encode both intended and
current states in the path, and link the tracking issue in metadata. The corpus test
asserts the current behavior, so a later detector fix makes the quarantine fail until the
fixture is promoted to the normal expected-state path.

## Retention and privacy

- Keep the newest verified fixture for each scenario/UI shape.
- Retain an older CLI version only when its distinct shape remains intentionally supported.
- Remove byte-equivalent history.
- Never commit raw captures, credentials, real-session user prompts/model output, account
  names, home paths, or repository names. Purpose-built scripted probes are allowed as
  described above; replace any output that exposes private configuration or persona text.
- Reconstructed and synthetic screens stay inline in `ScreenHeuristicsTests.swift`; they
  must not be version-stamped as captured evidence here.
