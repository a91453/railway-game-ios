#!/usr/bin/env bash
# Tests testflight-bundle.sh with a fake archive and a fake secret: the
# archive comes back byte for byte (symbolic links too), a changed file, a
# wrong SHA-256, another run's key and another secret are refused, and
# nothing is overwritten. Runs anywhere bash, tar and openssl run (also
# bash 3.2 and LibreSSL on macOS); used by testflight-checks.yml on Linux
# and in the macOS dry run.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/testflight-bundle.sh"
root="$(mktemp -d "${TMPDIR:-/tmp}/testflight-bundle-test.XXXXXX")"
trap 'rm -rf "$root"' EXIT
failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

make_archive() {
  local work="$1"
  mkdir -p "$work/RailwayGame.xcarchive/Products/Applications/RailwayGame.app"
  printf 'binary\0with nul\n' >"$work/RailwayGame.xcarchive/Products/Applications/RailwayGame.app/RailwayGame"
  head -c 300000 /dev/urandom >"$work/RailwayGame.xcarchive/Products/Applications/RailwayGame.app/data.bin"
  ln -s RailwayGame "$work/RailwayGame.xcarchive/Products/Applications/RailwayGame.app/link"
  printf '<plist/>\n' >"$work/RailwayGame.xcarchive/Info.plist"
  printf '<plist>upload</plist>\n' >"$work/UploadOptions.plist"
}

# Runs the script with the archive at $1 and the given secret and run.
bundle() {
  local work="$1" secret="$2" run="$3"
  shift 3
  ARCHIVE_PATH="$work/RailwayGame.xcarchive" UPLOAD_OPTIONS="$work/UploadOptions.plist" \
    BUNDLE_SECRET="$secret" GITHUB_RUN_ID="$run" RUNNER_TEMP="$root" "$script" "$@"
}

make_archive "$root/from"
secret="-----BEGIN PRIVATE KEY-----
fake
-----END PRIVATE KEY-----"
sha="$(bundle "$root/from" "$secret" 42 pack "$root/bundle.bin" 2>"$root/err")" || fail "pack: $(cat "$root/err")"
if [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then pass "pack prints a SHA-256"; else fail "pack printed '$sha'"; fi
if grep -q "with nul" "$root/bundle.bin"; then fail "the bundle holds plain text"; else pass "the bundle is not plain text"; fi
if ls "$root"/testflight-bundle-key.* >/dev/null 2>&1; then fail "the key file was left behind"; else pass "the key file is removed"; fi

if bundle "$root/to" "$secret" 42 unpack "$root/bundle.bin" "$sha" >/dev/null 2>"$root/err" &&
  diff -r "$root/from" "$root/to" >/dev/null &&
  [[ "$(readlink "$root/to/RailwayGame.xcarchive/Products/Applications/RailwayGame.app/link")" == RailwayGame ]]; then
  pass "unpack gives back the same archive and upload options"
else
  fail "unpack: $(cat "$root/err")"
fi

if bundle "$root/to" "$secret" 42 unpack "$root/bundle.bin" "$sha" >/dev/null 2>&1; then
  fail "unpack overwrote an archive that was already there"
else
  pass "unpack does not overwrite"
fi

expect_refused() {
  local name="$1"
  shift
  rm -rf "$root/other"
  if bundle "$root/other" "$@" >/dev/null 2>&1 && [[ -d "$root/other/RailwayGame.xcarchive" ]]; then
    fail "$name was accepted"
  else
    pass "$name is refused"
  fi
}
expect_refused "a wrong SHA-256" "$secret" 42 unpack "$root/bundle.bin" "$(printf '0%.0s' $(seq 64))"
expect_refused "a malformed SHA-256" "$secret" 42 unpack "$root/bundle.bin" "abc"
expect_refused "another run's key" "$secret" 43 unpack "$root/bundle.bin" "$sha"
expect_refused "another secret" "other" 42 unpack "$root/bundle.bin" "$sha"
expect_refused "an empty secret" "" 42 unpack "$root/bundle.bin" "$sha"
cp "$root/bundle.bin" "$root/changed.bin"
printf 'x' >>"$root/changed.bin"
expect_refused "a changed file" "$secret" 42 unpack "$root/changed.bin" "$sha"
expect_refused "a missing file" "$secret" 42 unpack "$root/missing.bin" "$sha"

if bundle "$root/empty" "$secret" 42 pack "$root/none.bin" >/dev/null 2>&1; then
  fail "pack with no archive succeeded"
else
  pass "pack with no archive is refused"
fi
if ARCHIVE_PATH="$root/from/RailwayGame.xcarchive" UPLOAD_OPTIONS="$root/elsewhere/UploadOptions.plist" \
  BUNDLE_SECRET="$secret" GITHUB_RUN_ID=42 "$script" pack "$root/x.bin" >/dev/null 2>&1; then
  fail "options in another folder were accepted"
else
  pass "options in another folder are refused"
fi

if ((failures > 0)); then
  echo "$failures check(s) failed."
  exit 1
fi
echo "All bundle checks passed."
