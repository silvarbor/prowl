# 016 — Dev Build & CI Workflow: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-04 | `make ensure-ghostty`: auto-sync GhosttyKit by submodule SHA (`.ghostty_hash` + `.ghostty_build_stamp`), DerivedData clear on SHA change, `sync-ghostty` force path; repo-managed git hooks | PR #140 |
| 2026-04-04 | Repo hook override reverted same day (`.githooks/`, `setup-local-hooks` removed); global hooks respected | commit `72a3dd2e` |
| 2026-04-04 | CI Ghostty cache includes marker files, `ghostty-v1` namespace, markers refreshed after restore so `ensure-ghostty` fast-paths on clean runners | PR #142 |
| 2026-04-04 | `make test` via xcsift TOON, persisted `.xcresult`, exit code via `PIPESTATUS[0]`, `scripts/print-xcresult-failures.sh` on failure, CI xcresult artifact upload | PR #144 |
| 2026-04-04 | Local test-warning cleanup; CI JavaScript actions on Node 24 runtime | PR #145 |
| 2026-04-05 | `embed-cli-debug` target: Debug app builds embed a debug-mode CLI; release `embed-cli` kept for `archive` | PR #152 |
| 2026-04-29 | swift-format ↔ SwiftLint trailing-comma conflict resolved; `make lint` became a pure check | PR #248 — see [002](002-format-lint-alignment.md) |
| 2026-05-08 | Superseded test workflow runs canceled via `concurrency` group | PR #266 — see [003](003-ci-throughput-and-caching.md) |
| 2026-05-09 | SPM cache moved from `/tmp` to `~/Library/Caches` to survive macOS `tmp_cleaner` | PR #269 — see [003](003-ci-throughput-and-caching.md) |
| 2026-05-19 | CI test steps parallelized after `build-app`; `test-app` target split out of `test` | PR #307 — see [003](003-ci-throughput-and-caching.md) |
| 2026-05-19 | Xcode compilation-cache CI key fixed (static `-v0` → content-keyed `-v1`); type-checker hotspot refactors; `COMPILATION_CACHE_ENABLE_CACHING`/`EAGER_LINKING` for Debug | PR #308 — see [003](003-ci-throughput-and-caching.md) |
| 2026-05-24 | Parallel test step no longer masks failures (`run_task` bash exit-status bug) | PR #333 — see [003](003-ci-throughput-and-caching.md) |
| 2026-06-05 | `make run-app` guard removed; debug run allowed alongside an existing Prowl instance | PR #391 — see [004](004-debug-identity-and-dev-loop.md) |
| 2026-06-14 | `ensure-ghostty` fronted by pinned prebuilt-artifact download; local Zig build becomes the fallback | PR #450 — see [041](../041-ghosttykit-prebuilt-artifacts/000-plan.md) |
| 2026-06-17 | `build-app` inputs made content-aware (`ProwlVersion.swift` sync, CLI embed copy) to stop rebuild churn | PR #461 — see [004](004-debug-identity-and-dev-loop.md) |
| 2026-06-19 | Stable Debug identity (`Prowl Debug` / `com.onevcat.prowl.debug`) at Xcode project level; `install-dev-build` back to plain `ditto` | PR #479 — see [004](004-debug-identity-and-dev-loop.md) |
| 2026-06-20 | `run-app` accelerated: `-showBuildSettings` cache + `SWIFT_COMPILATION_MODE=incremental` for Debug | PR #482 — see [004](004-debug-identity-and-dev-loop.md) |
| 2026-06-24 | Trailing-comma lint violations on `main` fixed (`make check` red while CI green) | PR #503 — see [002](002-format-lint-alignment.md) |
| 2026-10-13 | CI runs `make format-lint` in the parallel checks task; setup-macos puts Xcode's `swift-format` on `PATH` | Issue #575 — see [002](002-format-lint-alignment.md) |

## Outcome & current state (as of 2026-07-12)

- **`Makefile`**: `ensure-ghostty` first runs `scripts/ensure-ghosttykit-artifacts.sh`
  (prebuilt download, entry 041); exit code 2 falls back to the #140 source-build path —
  compare `HEAD:ThirdParty/ghostty` against `.ghostty_hash`, `$(MAKE) -B
  build-ghostty-xcframework`, clear `supacode-*` DerivedData on SHA change.
  `sync-ghostty` and `_record-ghostty-hash` survive as designed. `build-app` depends on
  `ensure-ghostty embed-cli-debug embed-docs` and pipes xcodebuild through
  `mise exec -- xcsift -w --format toon` with `SWIFT_COMPILATION_MODE=incremental`.
- **Test targets**: `test` is now `ensure-ghostty embed-cli-debug embed-docs test-app`
  (#307 split); `test-app` keeps the #144 shape — result bundle at
  `build/test-results/supacode-tests.xcresult`, `PIPESTATUS[0]` exit-code preservation,
  `scripts/print-xcresult-failures.sh` on failure. `test-cli-smoke` / `test-cli-integration`
  are separate SwiftPM-based targets (entry 013).
- **CLI embedding**: `embed-cli-debug` is a file rule on `Resources/prowl-cli/prowl` with
  `CLI_SOURCE_INPUTS` prerequisites and a `cmp -s` copy guard (#152 + #461);
  `sync-cli-version` only rewrites `supacode/CLIService/Shared/ProwlVersion.swift` when the
  version actually changed (#461). `archive` still uses the release universal `embed-cli`.
- **CI workflow** (`.github/workflows/test.yml`): `concurrency` group with
  `cancel-in-progress` (#266); `make lint` → `make build-app` → a parallel step running
  `make test-app`, `make test-cli-smoke`, `make test-cli-integration` via `run_task`
  with the #333 exit-status capture (the fix is documented in an inline comment);
  xcresult artifact upload on failure (#144); `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` (#145).
- **CI caches** (`.github/actions/setup-macos/action.yml`): mise cache; Ghostty cache
  keyed `ghostty-v1-<submodule SHA>` including both marker files, plus an unconditional
  "Sync ghostty marker files" step (#142); SPM cache at
  `~/Library/Caches/supacode-spm-cache/SourcePackages` (#269, matching `SPM_CACHE_DIR` in
  the Makefile); Xcode compilation cache keyed
  `xcode-compilation-cache-v1-${{ hashFiles('Package.resolved', 'supacode.xcodeproj/project.pbxproj') }}`
  with `restore-keys` fallback (#308).
- **Project settings** (`supacode.xcodeproj/project.pbxproj`): Debug configurations carry
  `PRODUCT_NAME = "Prowl Debug"`, `PRODUCT_BUNDLE_IDENTIFIER = com.onevcat.prowl.debug`,
  `ENABLE_DEBUG_DYLIB = NO`, `INFOPLIST_KEY_CFBundleDisplayName = "Prowl Debug"`, and the
  test target's Debug `TEST_HOST` points at `Prowl Debug.app` (#479);
  `COMPILATION_CACHE_ENABLE_CACHING = YES` at project- and target-Debug level (Release
  target sets `NO`) and `EAGER_LINKING = YES` for Debug (#308).
- **Dev loop**: `run-app` / `install-dev-build` read xcodebuild settings from
  `.build_settings_cache.json`, invalidated by `project.pbxproj` mtime (#482);
  `install-dev-build` is a guarded plain `ditto` copy with no re-signing (#479); `run-app`
  launches the Debug executable directly with no running-instance guard (#391).
  `.gitignore` covers `.ghostty_hash`, `.ghostty_build_stamp`, `.build_settings_cache.json`.
- **Formatting/lint**: see [002](002-format-lint-alignment.md); `check` =
  `format-changed format-lint lint`, `lint` is check-only, `.swiftlint.yml` disables
  `trailing_comma`.

## Deviations from plan

- The #140 repo-managed git hooks (`.githooks/`, `make setup-local-hooks`) were removed
  the same day (commit `72a3dd2e`); nothing hook-based remains.
- The SHA-compare fast path is no longer the first line of `ensure-ghostty`: since #450
  (entry 041) the pinned prebuilt-artifact download runs first and the #140 logic is the
  fallback for unpinned SHAs/download failures.
- `make test` no longer runs CLI tests implicitly and delegates the xcodebuild invocation
  to the `test-app` sub-target (#307); CI runs the three test suites in parallel instead
  of a single serial `make test`.

## Open questions

- ~~CI still runs only `make lint`, not `make format-lint`, so `main` can again turn red for
  `make check` while CI stays green — exactly the gap #503 patched around rather than
  closed.~~ Closed by #575: CI now runs `make format-lint`.
- The Ghostty cache payload still includes `.ghostty_hash` / `.ghostty_build_stamp` (#142),
  but the later unconditional "Sync ghostty marker files" step rewrites both after every
  restore, making the cached copies redundant — harmless leftover, never cleaned up.
- The `.build_settings_cache.json` invalidation (#482) only watches `project.pbxproj`
  mtime; an Xcode upgrade or DerivedData relocation that changes `BUILT_PRODUCTS_DIR`
  without touching the project file would keep serving stale paths until the cache file is
  deleted by hand.
