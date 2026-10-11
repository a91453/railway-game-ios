#!/usr/bin/env bash
# Tests testflight-retry.sh with a fake command and a fake sleep: how many
# attempts run, the exit status, the waits between attempts, the folder
# removed before each attempt, and the refusal of bad settings.
#
# Runs anywhere bash runs (also bash 3.2); used by testflight-checks.yml on
# Linux and on macOS.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
retry="$here/testflight-retry.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A sleep that records how long it was asked to wait instead of waiting.
mkdir "$tmp/bin"
cat >"$tmp/bin/sleep" <<'SH'
#!/usr/bin/env bash
echo "$1" >>"$SLEEP_LOG"
SH
chmod +x "$tmp/bin/sleep"

# fake <fail times> <exit status>: fails that many times, then succeeds.
# Each call is counted, and fails if the folder to clean is still there.
cat >"$tmp/fake" <<'SH'
#!/usr/bin/env bash
count=$(($(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1))
echo "$count" >"$COUNT_FILE"
if [[ -n "${CLEAN_CHECK:-}" ]]; then
  if [[ -e "$CLEAN_CHECK" ]]; then
    echo "left over from the previous attempt"
    exit 99
  fi
  mkdir -p "$CLEAN_CHECK/partial"
fi
if ((count <= $1)); then
  exit "$2"
fi
SH
chmod +x "$tmp/fake"

failures=0
cases=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# run <name> <expected exit> [VAR=value ...] -- <retry arguments...>
run() {
  local name="$1" expected="$2"
  shift 2
  local vars=()
  while [[ "$1" != "--" ]]; do
    vars+=("$1")
    shift
  done
  shift
  cases=$((cases + 1))
  rm -f "$tmp/$name.count" "$tmp/$name.sleeps"
  local status=0
  env -i PATH="$tmp/bin:$PATH" COUNT_FILE="$tmp/$name.count" SLEEP_LOG="$tmp/$name.sleeps" \
    ${vars[@]+"${vars[@]}"} bash "$retry" "$@" >"$tmp/$name.log" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    fail "$name: exit $status, expected $expected"
    sed 's/^/    /' "$tmp/$name.log"
  fi
}
expect_calls() {
  local actual
  actual="$(cat "$tmp/$1.count" 2>/dev/null || echo 0)"
  [[ "$actual" == "$2" ]] || fail "$1: the command ran $actual times, expected $2"
}
expect_sleeps() {
  local actual
  actual=""
  if [[ -f "$tmp/$1.sleeps" ]]; then
    actual="$(tr '\n' ' ' <"$tmp/$1.sleeps")"
  fi
  [[ "$actual" == "$2" ]] || fail "$1: waited '$actual', expected '$2'"
}
expect_log() {
  grep -qF -- "$2" "$tmp/$1.log" || fail "$1: no line containing '$2'"
}
expect_no_log() {
  if grep -qF -- "$2" "$tmp/$1.log"; then fail "$1: unexpected line containing '$2'"; fi
}

# --- Attempts, exit status and waits ----------------------------------------
run first-try 0 -- Export "$tmp/fake" 0 70
expect_calls first-try 1
expect_sleeps first-try ""
expect_no_log first-try "::warning::"
expect_no_log first-try "succeeded on attempt"

run third-try 0 -- Export "$tmp/fake" 2 70
expect_calls third-try 3
expect_sleeps third-try "30 60 "
expect_log third-try "::warning::Export failed (exit 70) on attempt 1 of 3; trying again in 30s."
expect_log third-try "::warning::Export failed (exit 70) on attempt 2 of 3; trying again in 60s."
expect_log third-try "Export succeeded on attempt 3 of 3."

run always-fails 70 -- Upload "$tmp/fake" 9 70
expect_calls always-fails 3
expect_sleeps always-fails "30 60 "
expect_log always-fails "::error::Upload failed (exit 70) on all 3 attempts."

run other-status 65 RETRY_DELAY=0 -- Upload "$tmp/fake" 9 65
expect_calls other-status 3
expect_sleeps other-status "0 0 "
expect_log other-status "on all 3 attempts"

run one-attempt 70 RETRY_ATTEMPTS=1 -- Export "$tmp/fake" 9 70
expect_calls one-attempt 1
expect_sleeps one-attempt ""

run five-attempts 0 RETRY_ATTEMPTS=5 RETRY_DELAY=5 -- Export "$tmp/fake" 4 1
expect_calls five-attempts 5
expect_sleeps five-attempts "5 10 20 40 "

# Arguments reach the command unchanged, spaces included.
cat >"$tmp/args" <<'SH'
#!/usr/bin/env bash
printf '<%s>' "$@" >"$COUNT_FILE"
SH
chmod +x "$tmp/args"
run arguments 0 -- "Label with spaces" "$tmp/args" "two words" "" "a*b"
[[ "$(cat "$tmp/arguments.count")" == "<two words><><a*b>" ]] ||
  fail "arguments: the command got $(cat "$tmp/arguments.count")"

# --- The folder to clean is gone before every attempt ------------------------
mkdir -p "$tmp/export/stale"
run clean 0 RETRY_DELAY=0 RETRY_CLEAN="$tmp/export" CLEAN_CHECK="$tmp/export" -- Export "$tmp/fake" 2 70
expect_calls clean 3
expect_no_log clean "left over"
[[ -d "$tmp/export/partial" && ! -e "$tmp/export/stale" ]] ||
  fail "clean: the last attempt's folder is not the only thing left"

# --- Bad settings are refused before the command runs ------------------------
for value in 0 10 x -1; do
  run "attempts-$value" 64 RETRY_ATTEMPTS="$value" -- Export "$tmp/fake" 0 0
  expect_calls "attempts-$value" 0
done
for value in 601 x -1 01 1.5; do
  run "delay-$value" 64 RETRY_DELAY="$value" -- Export "$tmp/fake" 0 0
  expect_calls "delay-$value" 0
done
run delay-600 0 RETRY_DELAY=600 -- Export "$tmp/fake" 1 1
expect_sleeps delay-600 "600 "
run no-command 64 -- Export
run nothing 64 --

if ((failures > 0)); then
  echo "$failures of the checks failed ($cases runs)."
  exit 1
fi
echo "All retry checks passed ($cases runs)."
