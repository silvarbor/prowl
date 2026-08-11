# 030.011 — Codex Screen Profile: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Date** | 2026-08-07 |
| **Branch** | `feat/codex-screen-profile` |
| **PR** | #687 (stacked on #686) |
| **Plan** | [007-screen-profile-migration-plan.md](007-screen-profile-migration-plan.md), Phase 4 |

## Result

Codex state detection now runs through one runtime-owned typed Swift profile. The profile
constructs its live regions once from the canonical 24-non-empty-line detector input and
evaluates rules in explicit source order:

1. directory trust → `blocked / codex.directoryTrust`;
2. hook review → `blocked / codex.hookReview`;
3. sign-in selection → `blocked / codex.signIn`;
4. numbered choice plus live confirmation footer →
   `blocked / codex.confirmationFooter`;
5. structurally complete Yes/No choices → `blocked / codex.confirmationChoices`;
6. exact live bottom working footer → `working / codex.workingFooter`;
7. no match → `idle / fallback.noRuleMatched`.

Blocked therefore still outranks a retained working footer. Ordinary composer frames,
quoted directory-trust text, stale menus, completed response prose, and unsupported
working-like bullets remain idle with an explicit no-match reason.

`CodexScreenRegions` owns Codex prompt/menu/footer boundaries. It splits canonical text
once and derives the selected-choice windows, recent sign-in menu, and bottom working
footer without a generic matcher or named-region registry. Mechanical recent-line and
numbered-choice predicates keep one shared owner because Claude still uses them.

## Migration protocol

The migration used the two-commit parity protocol from the approved plan:

- `3d1d118d` added `AgentScreenSnapshot`, the non-production Codex profile, stable IDs,
  reason assertions, and a temporary legacy-parity harness. All 21 existing inline Codex
  call sites and all seven captured Codex fixtures compared the profile state against the
  production legacy detector.
- `616e8365` routed production to the proven profile, required every existing inline test
  to return a non-legacy reason, removed the temporary comparator, and deleted the legacy
  Codex classifier plus its private helpers.

At no point does a shipped production path run both classifiers. Other runtimes still use
their unchanged legacy detectors and continue to report `legacy.detector`.

## Behavior and ownership

No intentional state behavior changed. The 0.146.1 corpus remains entirely green, so no
Codex fixture entered quarantine and no capture-backed exception was needed. Existing
screen-only authority, canonical-tail semantics, exact `(agent, active-screen text)` cache
identity, 3-second working hold, polling, and display-state projection are unchanged.

The legacy Codex implementation and exclusive helpers were removed from
`ScreenHeuristics.swift`; shared helpers remain there until their last non-profile caller
moves. Profile rule IDs are unique and `codex.`-prefixed by test.

## Validation

TDD and parity evidence:

- profile tests initially failed to compile because the snapshot/profile APIs did not
  exist;
- the non-production profile then matched all 21 existing Codex inline cases and all seven
  captured fixtures;
- the production-routing test next failed in 12 Codex test methods because production
  still returned `legacy.detector`, then passed after the switch;
- focused profile, heuristic, corpus, result, cache, and benchmark-smoke tests: 58 passed;
- full app suite: xcsift reported 2,285 passed; xcresult independently verified 2,287
  tests and zero failures;
- `make check` passed;
- `make bench`: 6 passed. At `616e8365`, the complete 15-fixture corpus measured
  **2.960 ms median**, versus Phase 3's 3.116 ms (**-5.0%**). The profile derives shared
  regions once instead of repeatedly splitting the same Codex screen.

The host remained locked at `loginwindow`, so no new live CLI reason observation is
claimed. Current-version provenance comes from the detector-faithful Codex 0.146.1
captures recorded in [009](009-captured-screen-fixture-corpus.md); retry live
`prowl agents --json` when the GUI session is unlocked and on the final simulated
integration branch.
