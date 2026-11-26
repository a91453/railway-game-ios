#!/usr/bin/env bash
# Hands the archive from the TestFlight job that makes it to the job that
# uploads it (decision 1016), through a workflow artifact. This repository
# is public, and anyone signed in to GitHub can download a public run's
# artifacts, so the archive (the app with its released name, decision 783) is never stored
# as it is: it is encrypted with a key only the "testflight" environment can
# make, and the uploading job checks the encrypted file's SHA-256 before it
# decrypts it.
#
#   testflight-bundle.sh pack <file>          tar the archive and the upload
#                                             options, encrypt them into
#                                             <file>, and print the file's
#                                             SHA-256
#   testflight-bundle.sh unpack <file> <sha>  check <file>'s SHA-256, decrypt
#                                             it and put the archive and the
#                                             upload options back where
#                                             testflight-signing.sh says
#
# The key is SHA-256 of the run's ID and BUNDLE_SECRET (the App Store
# Connect private key in the release), so it is never written to the
# workflow, a log or an output, and differs from run to run. It is handed to
# openssl in a file only this user can read, never on a command line.
# openssl enc with an explicit digest, which the macOS openssl (LibreSSL)
# and OpenSSL 3 read the same way: the key is 256 random-looking bits, so the
# passphrase derivation adds nothing to guess.
#
# Inputs (environment): ARCHIVE_PATH and UPLOAD_OPTIONS (from
# testflight-signing.sh setup; the same folder), BUNDLE_SECRET,
# GITHUB_RUN_ID, RUNNER_TEMP. Runs on macOS (bash 3.2) and Linux. Tested by
# testflight-selftest-bundle.sh.
set -euo pipefail

usage() {
  echo "usage: $0 pack <file> | unpack <file> <sha256>" >&2
  exit 64
}

archive="${ARCHIVE_PATH:?ARCHIVE_PATH is not set; run testflight-signing.sh setup first}"
options="${UPLOAD_OPTIONS:?UPLOAD_OPTIONS is not set; run testflight-signing.sh setup first}"
folder="$(dirname "$archive")"
if [[ "$(dirname "$options")" != "$folder" ]]; then
  echo "::error::The archive and the upload options are not in one folder." >&2
  exit 1
fi
if [[ -z "${BUNDLE_SECRET:-}" ]]; then
  echo "::error::BUNDLE_SECRET is not set." >&2
  exit 1
fi
run="${GITHUB_RUN_ID:?GITHUB_RUN_ID is not set}"

sha256() {
  openssl dgst -sha256 -r "$1" | cut -c1-64
}

key_file="$(umask 077 && mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/testflight-bundle-key.XXXXXX")"
trap 'rm -f "$key_file"' EXIT
printf 'testflight-archive\n%s\n%s' "$run" "$BUNDLE_SECRET" | openssl dgst -sha256 -r | cut -c1-64 >"$key_file"

case "${1:-}" in
  pack)
    [[ $# -eq 2 ]] || usage
    out="$2"
    if [[ ! -d "$archive" || ! -f "$options" ]]; then
      echo "::error::No archive or upload options to pack." >&2
      exit 1
    fi
    tar -C "$folder" -cf - "$(basename "$archive")" "$(basename "$options")" |
      openssl enc -aes-256-cbc -md sha256 -salt -pass "file:$key_file" -out "$out"
    sha256 "$out"
    ;;
  unpack)
    [[ $# -eq 3 ]] || usage
    in="$2"
    expected="$3"
    if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
      echo "::error::The expected SHA-256 is not 64 hexadecimal digits." >&2
      exit 1
    fi
    if [[ ! -f "$in" ]]; then
      echo "::error::$in does not exist." >&2
      exit 1
    fi
    actual="$(sha256 "$in")"
    if [[ "$actual" != "$expected" ]]; then
      echo "::error::The encrypted archive is not the one the archive job made (SHA-256 $actual, expected $expected)." >&2
      exit 1
    fi
    if [[ -e "$archive" || -e "$options" ]]; then
      echo "::error::An archive or upload options are already there; not overwriting them." >&2
      exit 1
    fi
    mkdir -p "$folder"
    openssl enc -d -aes-256-cbc -md sha256 -pass "file:$key_file" -in "$in" | tar -C "$folder" -xf -
    if [[ ! -d "$archive" || ! -f "$options" ]]; then
      echo "::error::The decrypted file holds no archive or upload options." >&2
      exit 1
    fi
    echo "Archive and upload options unpacked."
    ;;
  *) usage ;;
esac
