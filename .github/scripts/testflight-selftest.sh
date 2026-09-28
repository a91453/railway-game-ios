#!/usr/bin/env bash
# Tests testflight-preflight.sh with fake values only (no Apple account, no
# real secrets): the passing case, every failure mode, the build-number
# scheme, and that no secret value ever reaches its output.
#
# Runs anywhere bash runs; used by testflight-checks.yml on Linux.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
preflight="$here/testflight-preflight.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Obviously fake values. The marker must never be printed.
marker="FAKE_PRIVATE_SECRET_DO_NOT_PRINT"
fake_key_id="FAKEKEY001"
fake_issuer="00000000-0000-4000-8000-00000000fa6e"
fake_key=$'-----BEGIN PRIVATE KEY-----\n'"$marker"$'\n-----END PRIVATE KEY-----'
valid=(
  GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main
  GITHUB_RUN_NUMBER=7 GITHUB_RUN_ATTEMPT=1
  APPLE_TEAM_ID=FAKETEAM01 ASC_APP_ID=1000000001
  ASC_KEY_ID="$fake_key_id" ASC_ISSUER_ID="$fake_issuer" ASC_PRIVATE_KEY="$fake_key"
)

failures=0
cases=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# run <name> <expected exit> [VAR=value ...]: runs the preflight with only the
# given environment; keeps its log and output for the checks below.
run() {
  local name="$1" expected="$2"
  shift 2
  cases=$((cases + 1))
  : >"$tmp/$name.out"
  : >"$tmp/$name.env"
  local status=0
  env -i PATH="$PATH" GITHUB_OUTPUT="$tmp/$name.out" GITHUB_ENV="$tmp/$name.env" "$@" \
    bash "$preflight" >"$tmp/$name.log" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    fail "$name: exit $status, expected $expected"
    sed 's/^/    /' "$tmp/$name.log"
  fi
}
build_number_of() { sed -n 's/^build_number=//p' "$tmp/$1.out"; }
expect_build() {
  local actual env_value
  actual="$(build_number_of "$1")"
  [[ "$actual" == "$2" ]] || fail "$1: build number '$actual', expected '$2'"
  env_value="$(sed -n 's/^BUILD_NUMBER=//p' "$tmp/$1.env")"
  [[ "$env_value" == "$2" ]] || fail "$1: BUILD_NUMBER in GITHUB_ENV is '$env_value', expected '$2'"
}
expect_error() {
  grep -qF -- "$2" "$tmp/$1.log" || fail "$1: no error containing '$2'"
}
expect_errors() {
  local count
  count="$(grep -c '^::error' "$tmp/$1.log" || true)"
  [[ "$count" -eq "$2" ]] || fail "$1: $count errors reported, expected all $2 at once"
}

# --- Passing cases and the build-number scheme ------------------------------
run valid 0 "${valid[@]}"
expect_build valid 7.1
run rerun 0 "${valid[@]}" GITHUB_RUN_ATTEMPT=2
expect_build rerun 7.2
run next-run 0 "${valid[@]}" GITHUB_RUN_NUMBER=8
expect_build next-run 8.1
run offset 0 "${valid[@]}" BUILD_NUMBER_OFFSET=100
expect_build offset 107.1
run offset-zero 0 "${valid[@]}" BUILD_NUMBER_OFFSET=0
expect_build offset-zero 7.1
run max-components 0 "${valid[@]}" GITHUB_RUN_NUMBER=9999 GITHUB_RUN_ATTEMPT=99
expect_build max-components 9999.99
run max-offset-sum 0 "${valid[@]}" GITHUB_RUN_NUMBER=7 BUILD_NUMBER_OFFSET=9992
expect_build max-offset-sum 9999.1
# Each later build number must sort after the earlier ones, as App Store
# Connect compares them: component by component, as integers.
ordered="$(printf '%s\n' 8.1 7.2 7.1 107.1 | sort -t. -k1,1n -k2,2n | tr '\n' ' ')"
[[ "$ordered" == "7.1 7.2 8.1 107.1 " ]] || fail "build numbers sort as '$ordered'"
# A .p8 pasted with CR line endings and a leading blank line is accepted.
run crlf-key 0 "${valid[@]}" ASC_PRIVATE_KEY=$'\r\n'"${fake_key//$'\n'/$'\r\n'}"$'\r\n'

# --- Failure modes: every problem is reported at once -----------------------
run nothing-set 1 GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main \
  GITHUB_RUN_NUMBER=7 GITHUB_RUN_ATTEMPT=1
expect_errors nothing-set 5
for name in APPLE_TEAM_ID ASC_APP_ID ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY; do
  expect_error nothing-set "$name is not set"
done
run not-main 1 "${valid[@]}" GITHUB_REF=refs/heads/feature
expect_errors not-main 1
expect_error not-main "only from main"
run tag 1 "${valid[@]}" GITHUB_REF=refs/tags/v1
expect_error tag "only from main"
run not-dispatch 1 "${valid[@]}" GITHUB_EVENT_NAME=push
expect_error not-dispatch "only by hand"
run malformed 1 "${valid[@]}" APPLE_TEAM_ID=faketeam01 ASC_APP_ID=io.github.x \
  ASC_KEY_ID=KEY ASC_ISSUER_ID=not-a-uuid BUILD_NUMBER_OFFSET=01 ASC_PRIVATE_KEY="$marker"
expect_errors malformed 6
expect_error malformed "APPLE_TEAM_ID must be"
expect_error malformed "ASC_APP_ID must be"
expect_error malformed "ASC_KEY_ID must be"
expect_error malformed "ASC_ISSUER_ID must be"
expect_error malformed "BUILD_NUMBER_OFFSET must be"
expect_error malformed "ASC_PRIVATE_KEY must be"
run truncated-key 1 "${valid[@]}" ASC_PRIVATE_KEY=$'-----BEGIN PRIVATE KEY-----\n'"$marker"
expect_error truncated-key "ASC_PRIVATE_KEY must be"
run negative-offset 1 "${valid[@]}" BUILD_NUMBER_OFFSET=-1
expect_error negative-offset "BUILD_NUMBER_OFFSET must be"
run too-large-offset 1 "${valid[@]}" BUILD_NUMBER_OFFSET=10000
expect_error too-large-offset "BUILD_NUMBER_OFFSET must be"
run offset-sum-too-large 1 "${valid[@]}" GITHUB_RUN_NUMBER=8 BUILD_NUMBER_OFFSET=9992
expect_error offset-sum-too-large "must not exceed 9999"
run too-large-run-number 1 "${valid[@]}" GITHUB_RUN_NUMBER=10000
expect_error too-large-run-number "GITHUB_RUN_NUMBER must be"
run too-large-attempt 1 "${valid[@]}" GITHUB_RUN_ATTEMPT=100
expect_error too-large-attempt "GITHUB_RUN_ATTEMPT must be"
run no-run-number 1 "${valid[@]}" GITHUB_RUN_NUMBER=
expect_error no-run-number "GITHUB_RUN_NUMBER"
for name in nothing-set not-main malformed truncated-key too-large-offset offset-sum-too-large too-large-run-number too-large-attempt; do
  [[ ! -s "$tmp/$name.out" && ! -s "$tmp/$name.env" ]] || fail "$name: wrote a build number despite failing"
done

# --- No secret in any output ------------------------------------------------
if grep -rlF -e "$marker" -e "$fake_key_id" -e "$fake_issuer" "$tmp" >"$tmp/leaks.txt" 2>/dev/null; then
  fail "secret values appear in: $(xargs -n1 basename <"$tmp/leaks.txt" | tr '\n' ' ')"
fi

if ((failures > 0)); then
  echo "$failures of the checks failed ($cases preflight runs)."
  exit 1
fi
echo "All preflight checks passed ($cases runs); no secret value was printed."
