#!/usr/bin/env bash
# Runs a TestFlight release command again when it fails, so that a dropped
# connection to Apple does not throw away the archive the job already built.
# Used by .github/workflows/testflight.yml for the two steps that talk to
# Apple after the archive: the export (cloud-managed distribution signing)
# and the upload. TestFlight run #48 lost its archive this way: the export
# failed with "The network connection was lost." (exit 70).
#
#   testflight-retry.sh <label> <command> [arguments...]
#
# Every failure is retried, whatever its cause: Apple's messages for a lost
# or timed-out connection vary, and a failure that is not transient only
# costs the extra attempts. A retried upload whose first attempt did reach
# App Store Connect is refused as a duplicate build number; the processing
# job (testflight-processing.py) still looks for the build and reports it.
#
# Inputs (environment, all optional):
#   RETRY_ATTEMPTS  attempts in all, 1 to 9; default 3
#   RETRY_DELAY     seconds before the second attempt, doubled before each
#                   later one; 0 to 600; default 30
#   RETRY_CLEAN     a path removed before every attempt (the export folder),
#                   so a failed attempt leaves nothing for the next to find
# Exit status: 0 when an attempt succeeds, otherwise the last attempt's.
# Runs under bash 3.2 (macOS). Tested by testflight-selftest-retry.sh.
set -euo pipefail

usage() {
  echo "usage: $0 <label> <command> [arguments...]" >&2
  exit 64
}
[[ $# -ge 2 ]] || usage
label="$1"
shift

attempts="${RETRY_ATTEMPTS:-3}"
delay="${RETRY_DELAY:-30}"
if [[ ! "$attempts" =~ ^[1-9]$ ]]; then
  echo "::error::RETRY_ATTEMPTS must be a whole number from 1 to 9." >&2
  exit 64
fi
if [[ ! "$delay" =~ ^(0|[1-9][0-9]{0,2})$ ]] || ((delay > 600)); then
  echo "::error::RETRY_DELAY must be a whole number of seconds from 0 to 600." >&2
  exit 64
fi

attempt=1
while true; do
  if [[ -n "${RETRY_CLEAN:-}" ]]; then
    rm -rf "$RETRY_CLEAN"
  fi
  status=0
  "$@" || status=$?
  if ((status == 0)); then
    if ((attempt > 1)); then
      echo "$label succeeded on attempt $attempt of $attempts."
    fi
    exit 0
  fi
  if ((attempt >= attempts)); then
    echo "::error::$label failed (exit $status) on all $attempts attempts."
    exit "$status"
  fi
  echo "::warning::$label failed (exit $status) on attempt $attempt of $attempts; trying again in ${delay}s."
  sleep "$delay"
  attempt=$((attempt + 1))
  delay=$((delay * 2))
done
