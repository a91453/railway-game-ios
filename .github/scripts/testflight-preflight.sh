#!/usr/bin/env bash
# Checks, before any macOS runner starts, that a TestFlight release may run
# and has everything it needs, then prints the build number for this run.
# Reports every problem at once and exits non-zero if there is any. Never
# prints a secret: it only tests whether values are set and well formed.
#
# Used by .github/workflows/testflight.yml twice: by the preflight job, to
# stop before a macOS runner starts, and first thing in the release job, so
# the build number always comes from the attempt that is running (a re-run
# of only the failed jobs reuses the earlier preflight job's results).
# Tested by testflight-selftest.sh. Inputs (environment):
#   GITHUB_EVENT_NAME, GITHUB_REF,
#   GITHUB_RUN_NUMBER, GITHUB_RUN_ATTEMPT  set by GitHub Actions
#   APPLE_TEAM_ID        variable: 10-character Team ID
#   ASC_APP_ID           variable: the app's Apple ID in App Store Connect
#   BUILD_NUMBER_OFFSET  variable, optional: whole number added to the run number
#   ASC_KEY_ID           secret: App Store Connect team API key ID
#   ASC_ISSUER_ID        secret: App Store Connect issuer ID
#   ASC_PRIVATE_KEY      secret: the whole text of AuthKey_<key id>.p8
# Output: build_number=<n>.<attempt> appended to $GITHUB_OUTPUT, and
# BUILD_NUMBER=<n>.<attempt> to $GITHUB_ENV, when those are set.
set -euo pipefail

guide="docs/TESTFLIGHT_GITHUB_ACTIONS.md"
problems=0
problem() {
  echo "::error title=TestFlight preflight::$1"
  problems=$((problems + 1))
}
# Succeeds if the named value is set; otherwise records a problem.
is_set() {
  local name="$1" kind="$2"
  if [[ -z "${!name:-}" ]]; then
    problem "The $kind $name is not set in the 'testflight' environment (see $guide)."
    return 1
  fi
}

if [[ "${GITHUB_EVENT_NAME:-}" != "workflow_dispatch" ]]; then
  problem "Releases start only by hand (Run workflow), not from '${GITHUB_EVENT_NAME:-unknown}'."
fi
if [[ "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
  problem "Releases run only from main; this run is on '${GITHUB_REF:-unknown}'."
fi

if is_set APPLE_TEAM_ID variable && [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  problem "The variable APPLE_TEAM_ID must be the 10-character Team ID (capital letters and digits)."
fi
if is_set ASC_APP_ID variable && [[ ! "$ASC_APP_ID" =~ ^[1-9][0-9]{5,14}$ ]]; then
  problem "The variable ASC_APP_ID must be the app's numeric Apple ID from App Store Connect (App Information)."
fi
offset="${BUILD_NUMBER_OFFSET:-0}"
offset_ok=true
if [[ ! "$offset" =~ ^(0|[1-9][0-9]{0,3})$ ]]; then
  problem "The variable BUILD_NUMBER_OFFSET must be a whole number from 0 to 9999."
  offset_ok=false
fi
if is_set ASC_KEY_ID secret && [[ ! "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  problem "The secret ASC_KEY_ID must be the 10-character API key ID."
fi
if is_set ASC_ISSUER_ID secret &&
  [[ ! "$ASC_ISSUER_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  problem "The secret ASC_ISSUER_ID must be the issuer ID shown above the API keys (a lowercase UUID)."
fi
if is_set ASC_PRIVATE_KEY secret; then
  # Pasting from some editors adds CR line endings or blank lines; accept them.
  key_text="$(printf '%s\n' "$ASC_PRIVATE_KEY" | tr -d '\r')"
  if [[ "$(sed -n '/./{p;q;}' <<<"$key_text")" != "-----BEGIN PRIVATE KEY-----" ]] ||
    ! grep -qx -- "-----END PRIVATE KEY-----" <<<"$key_text"; then
    problem "The secret ASC_PRIVATE_KEY must be the whole text of the .p8 file, from -----BEGIN PRIVATE KEY----- to -----END PRIVATE KEY-----."
  fi
fi

run_number="${GITHUB_RUN_NUMBER:-}"
attempt="${GITHUB_RUN_ATTEMPT:-}"
run_ok=true
if [[ ! "$run_number" =~ ^[1-9][0-9]{0,3}$ ]]; then
  problem "GITHUB_RUN_NUMBER must be an integer from 1 to 9999."
  run_ok=false
fi
if [[ ! "$attempt" =~ ^[1-9][0-9]?$ ]]; then
  problem "GITHUB_RUN_ATTEMPT must be an integer from 1 to 99."
  run_ok=false
fi
if [[ "$offset_ok" == true && "$run_ok" == true ]] && ((offset + run_number > 9999)); then
  problem "BUILD_NUMBER_OFFSET + GITHUB_RUN_NUMBER must not exceed 9999."
fi

if ((problems > 0)); then
  echo "Preflight found $problems problem(s). Nothing was built, signed or uploaded."
  exit 1
fi

# <offset + run number>.<attempt>. Apple limits CFBundleVersion's first
# integer to four digits and the second to two, so preflight enforces
# <= 9999 and <= 99 before constructing it. A new run gets a higher first
# number and a re-run of that run a higher second number.
build_number="$((offset + run_number)).$attempt"
echo "Preflight passed. Build number for this run: $build_number"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "build_number=$build_number" >>"$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "BUILD_NUMBER=$build_number" >>"$GITHUB_ENV"
fi
