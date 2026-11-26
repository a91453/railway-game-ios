#!/usr/bin/env bash
# Names the UI tests that failed and then passed when xcodebuild ran them
# again (-retry-tests-on-failure, decision 582's later note), from the
# xcodebuild output in $1, so a test that passes only on its second try is
# still seen: one ::warning:: each and a line in the step summary. A test
# that failed every time is left to xcodebuild's own failure.
#
#   ui-retry-report.sh <xcodebuild log> [<job name>]
#   ui-retry-report.sh --selftest
set -euo pipefail

report() {
  local log="$1" job="${2:-UI tests}"
  [[ -f "$log" ]] || { echo "No UI test log at $log"; return 0; }
  local failed passed retried
  failed="$(sed -nE "s/^.*Test Case '-\[([A-Za-z0-9_]+)\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' failed.*$/\2\/\3/p" "$log" | sort -u)"
  passed="$(sed -nE "s/^.*Test Case '-\[([A-Za-z0-9_]+)\.([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\]' passed.*$/\2\/\3/p" "$log" | sort -u)"
  retried="$(comm -12 <(printf '%s\n' "$failed") <(printf '%s\n' "$passed") | sed '/^$/d')"
  if [[ -z "$retried" ]]; then
    echo "$job: no UI test passed only on a retry."
    return 0
  fi
  local count
  count="$(printf '%s\n' "$retried" | wc -l | tr -d ' ')"
  {
    echo "- **$job: $count UI test(s) failed once and passed on the retry** (flaky; see the log for the first failure):"
    # shellcheck disable=SC2016 # the backticks are Markdown, not a command
    printf '%s\n' "$retried" | sed 's/^/  - `/; s/$/`/'
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  while IFS= read -r test; do
    echo "::warning::$job: $test failed once and passed on the retry (flaky)."
  done <<<"$retried"
}

selftest() {
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  cat >"$dir/log" <<'EOF'
2026-11-26T02:43:29.1006750Z Test Case '-[RailwayGameUITests.MapInteractionTests testTheFleetListScrollsFromADragOnACard]' failed (30.521 seconds).
2026-11-26T02:44:29.1006750Z Test Case '-[RailwayGameUITests.MapInteractionTests testTheFleetListScrollsFromADragOnACard]' passed (28.000 seconds).
2026-11-26T02:53:29.2338070Z Test Case '-[RailwayGameUITests.MapInteractionTests testTheTrackOptionsShowWhetherTheyAreOn]' failed (142.760 seconds).
2026-11-26T02:56:29.2338070Z Test Case '-[RailwayGameUITests.MapInteractionTests testTheTrackOptionsShowWhetherTheyAreOn]' failed (140.000 seconds).
2026-11-26T02:57:29.2338070Z Test Case '-[RailwayGameUITests.ToolbarSmokeTests testEnglishToolbar]' passed (35.429 seconds).
EOF
  local out
  out="$(GITHUB_STEP_SUMMARY="$dir/summary" report "$dir/log" "Selftest")"
  [[ "$out" == "::warning::Selftest: MapInteractionTests/testTheFleetListScrollsFromADragOnACard failed once and passed on the retry (flaky)." ]] \
    || { echo "selftest: unexpected warnings: $out"; return 1; }
  grep -q "1 UI test(s) failed once" "$dir/summary" || { echo "selftest: no summary line"; return 1; }
  : >"$dir/clean"
  out="$(GITHUB_STEP_SUMMARY="$dir/summary2" report "$dir/clean" "Selftest")"
  [[ "$out" == "Selftest: no UI test passed only on a retry." ]] || { echo "selftest: clean log said: $out"; return 1; }
  [[ ! -s "$dir/summary2" ]] || { echo "selftest: clean log wrote a summary"; return 1; }
  echo "ui-retry-report selftest passed"
}

if [[ "${1:-}" == --selftest ]]; then
  selftest
else
  report "$@"
fi
