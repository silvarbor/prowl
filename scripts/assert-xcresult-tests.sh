#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "usage: $0 <xcresult-path> [expected-test-count]" >&2
  exit 2
fi

result_bundle="$1"
expected_test_count="${2:-}"
if [[ -n "$expected_test_count" && ! "$expected_test_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: expected test count must be a positive integer: $expected_test_count" >&2
  exit 2
fi

if [[ ! -d "$result_bundle" ]]; then
  echo "error: xcresult bundle not found: $result_bundle" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to validate xcresult test counts" >&2
  exit 1
fi

summary_json="$(mktemp)"
cleanup() {
  rm -f "$summary_json"
}
trap cleanup EXIT

if ! xcrun xcresulttool get test-results summary --path "$result_bundle" --compact >"$summary_json"; then
  echo "error: failed to parse xcresult test summary: $result_bundle" >&2
  exit 1
fi

read -r result total_tests failed_tests < <(
  jq -er '
    def numeric:
      if type == "number" then .
      elif type == "string" then tonumber
      else error("expected numeric test count")
      end;
    [
      (.result // "Unknown"),
      ((.totalTestCount // 0) | numeric),
      ((.failedTests // 0) | numeric)
    ] | @tsv
  ' "$summary_json"
)

if [[ "$result" != "Passed" ]]; then
  echo "error: xcresult test result is $result, expected Passed" >&2
  exit 1
fi

if (( failed_tests != 0 )); then
  echo "error: xcresult reports $failed_tests failed test(s)" >&2
  exit 1
fi

if (( total_tests <= 0 )); then
  echo "error: xcresult reports zero tests; refusing a false-success test run" >&2
  exit 1
fi

if [[ -n "$expected_test_count" ]] && (( total_tests != expected_test_count )); then
  echo "error: expected $expected_test_count tests, found $total_tests" >&2
  exit 1
fi

echo "Verified xcresult: $total_tests test(s), zero failures."
