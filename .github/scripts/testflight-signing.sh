#!/usr/bin/env bash
# Sets up and tears down what a TestFlight release job signs with.
#
#   testflight-signing.sh setup    create a temporary keychain and make it the
#                                  default, and write the App Store Connect
#                                  API key (when given) to a private file
#   testflight-signing.sh cleanup  restore the previous keychains and delete
#                                  the temporary keychain, the key file, any
#                                  provisioning profile the job added, and
#                                  the archive and IPA
#
# No certificate or profile is imported: xcodebuild gets them through the API
# key (automatic signing, and Apple's cloud-managed distribution certificate
# at export). The temporary keychain becomes the default so that whatever
# Xcode creates while signing, such as a development signing identity, lands
# in it and is deleted with it. Cleanup always exits 0 and is safe to run
# twice or after a failed or partial setup.
#
# macOS only. Inputs (environment): RUNNER_TEMP, HOME, GITHUB_ENV (set by
# GitHub Actions); ASC_KEY_ID and ASC_PRIVATE_KEY (secrets; omitted in dry
# runs). Exports to later steps: TESTFLIGHT_DIR, ARCHIVE_PATH, EXPORT_PATH,
# EXPORT_OPTIONS, UPLOAD_OPTIONS and, with a key, ASC_KEY_PATH.
set -euo pipefail

work="${RUNNER_TEMP:?RUNNER_TEMP is not set}/testflight"
state="$RUNNER_TEMP/testflight-state"
keychain="$state/signing.keychain-db"
profile_dirs=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

list_profiles() {
  local dir
  for dir in "${profile_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      find "$dir" -type f
    fi
  done
}

# Reads the saved keychain list into the array `keychains`.
read_saved_keychains() {
  keychains=()
  local line
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      keychains+=("$line")
    fi
  done <"$state/keychains"
}

setup() {
  umask 077
  if [[ -e "$state" ]]; then
    echo "::error::$state already exists; run cleanup first."
    exit 1
  fi
  mkdir -p "$state" "$work"

  # Remember the user keychains so cleanup can put them back.
  security default-keychain -d user | sed -e 's/^ *"//' -e 's/"$//' >"$state/default-keychain"
  security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//' >"$state/keychains"
  list_profiles | sort >"$state/profiles-before"

  # A random password that is used only here and never stored.
  local password
  password="$(openssl rand -hex 32)"
  echo "::add-mask::$password"
  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  local keychains
  read_saved_keychains
  # ${a[@]+...} keeps an empty array safe under set -u in bash 3.2.
  security list-keychains -d user -s "$keychain" ${keychains[@]+"${keychains[@]}"}
  security default-keychain -d user -s "$keychain"
  echo "Temporary keychain created, unlocked and made the default."

  {
    echo "TESTFLIGHT_DIR=$work"
    echo "ARCHIVE_PATH=$work/RailwayGame.xcarchive"
    echo "EXPORT_PATH=$work/export"
    echo "EXPORT_OPTIONS=$work/ExportOptions.plist"
    echo "UPLOAD_OPTIONS=$work/UploadOptions.plist"
  } >>"${GITHUB_ENV:-/dev/null}"

  if [[ -n "${ASC_PRIVATE_KEY:-}" ]]; then
    local key_dir="$state/private_keys"
    local key_path="$key_dir/AuthKey_${ASC_KEY_ID:?ASC_KEY_ID is not set}.p8"
    mkdir -p "$key_dir"
    # Drop CR line endings and leading blank lines a paste may have added.
    printf '%s\n' "$ASC_PRIVATE_KEY" | tr -d '\r' | sed '/./,$!d' >"$key_path"
    chmod 600 "$key_path"
    echo "ASC_KEY_PATH=$key_path" >>"${GITHUB_ENV:-/dev/null}"
    echo "App Store Connect API key written to a file only this job's user can read."
  else
    echo "No App Store Connect API key given (dry run)."
  fi
}

cleanup() {
  set +e
  local keychains
  if [[ -s "$state/keychains" ]]; then
    read_saved_keychains
    security list-keychains -d user -s ${keychains[@]+"${keychains[@]}"}
  fi
  if [[ -s "$state/default-keychain" ]]; then
    security default-keychain -d user -s "$(cat "$state/default-keychain")"
  fi
  if [[ -e "$keychain" ]]; then
    security delete-keychain "$keychain" && echo "Temporary keychain deleted."
  fi

  local removed=0 profile
  if [[ -f "$state/profiles-before" ]]; then
    while IFS= read -r profile; do
      rm -f "$profile" && removed=$((removed + 1))
    done < <(list_profiles | sort | comm -13 "$state/profiles-before" -)
  fi
  echo "Provisioning profiles added by this job and removed: $removed."

  # The key file, the archive and the IPA (which embeds the provisioning
  # profile) are never uploaded as artifacts; delete them here.
  rm -rf "$state" "$work"
  echo "Key file, archive and IPA removed."
  return 0
}

case "${1:-}" in
  setup) setup ;;
  cleanup) cleanup ;;
  *)
    echo "usage: $0 setup|cleanup" >&2
    exit 64
    ;;
esac
