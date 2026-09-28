#!/usr/bin/env bash
# Checks that an exported IPA is the App Store distribution build this
# release expects, before it is uploaded. Reports every problem at once and
# exits non-zero if there is any.
#
# Prints only yes/no answers and version facts, never a certificate name:
# certificate names carry the account holder's name, and this repository's
# Actions logs are public.
#
# Usage: testflight-verify-ipa.sh <path/to/App.ipa>
# Inputs (environment): EXPECTED_BUNDLE_ID, EXPECTED_VERSION, EXPECTED_BUILD,
# EXPECTED_TEAM_ID; GITHUB_STEP_SUMMARY (optional). macOS tools: unzip,
# codesign, security, PlistBuddy (PLISTBUDDY overrides its path for tests).
set -euo pipefail

ipa="${1:?usage: $0 <path/to/App.ipa>}"
bundle_id="${EXPECTED_BUNDLE_ID:?EXPECTED_BUNDLE_ID is not set}"
version="${EXPECTED_VERSION:?EXPECTED_VERSION is not set}"
build="${EXPECTED_BUILD:?EXPECTED_BUILD is not set}"
team="${EXPECTED_TEAM_ID:?EXPECTED_TEAM_ID is not set}"
plistbuddy="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

failures=0
fail() {
  echo "::error title=IPA check::$1"
  failures=$((failures + 1))
}
# value <key path> <plist>: prints the value, or "(missing)".
value() {
  "$plistbuddy" -c "Print :$1" "$2" 2>/dev/null || echo "(missing)"
}
yes_no() { if "$@"; then echo yes; else echo no; fi; }

unpacked="$(mktemp -d "${TMPDIR:-/tmp}/ipa-check.XXXXXX")"
trap 'rm -rf "$unpacked"' EXIT

if ! unzip -q "$ipa" -d "$unpacked" 2>/dev/null; then
  fail "The IPA is not a readable zip archive."
  exit 1
fi
shopt -s nullglob
apps=("$unpacked"/Payload/*.app)
if [[ ${#apps[@]} -ne 1 ]]; then
  fail "Expected exactly one app in Payload/, found ${#apps[@]}."
  exit 1
fi
app="${apps[0]}"
info="$app/Info.plist"

# --- Structure --------------------------------------------------------------
structure_ok=true
executable="$(value CFBundleExecutable "$info")"
for part in "$executable" Assets.car _CodeSignature/CodeResources embedded.mobileprovision; do
  if [[ ! -e "$app/$part" ]]; then
    fail "The app has no $part."
    structure_ok=false
  fi
done

# --- Identity and version ---------------------------------------------------
actual_bundle_id="$(value CFBundleIdentifier "$info")"
actual_version="$(value CFBundleShortVersionString "$info")"
actual_build="$(value CFBundleVersion "$info")"
[[ "$actual_bundle_id" == "$bundle_id" ]] ||
  fail "The bundle identifier is $actual_bundle_id, not $bundle_id."
[[ "$actual_version" == "$version" ]] ||
  fail "The version is $actual_version, not $version."
[[ "$actual_build" == "$build" ]] ||
  fail "The build number is $actual_build, not $build."

# --- Signature --------------------------------------------------------------
if ! codesign --verify --strict "$app" 2>/dev/null; then
  fail "The app's code signature does not verify."
fi
signature="$(codesign --display --verbose=2 "$app" 2>&1 || true)"
leaf="$(sed -n 's/^Authority=//p' <<<"$signature" | head -n 1)"
case "$leaf" in
  "Apple Distribution:"* | "iPhone Distribution:"*) distribution=yes ;;
  "Apple Development:"* | "iPhone Developer:"*)
    distribution=no
    fail "The app is signed with a development certificate, not a distribution one."
    ;;
  *)
    distribution=no
    if grep -q '^Signature=adhoc' <<<"$signature"; then
      fail "The app is signed ad hoc, not with a distribution certificate."
    else
      fail "The app is not signed with a distribution certificate."
    fi
    ;;
esac

app_identifier="$team.$bundle_id"
entitlements="$unpacked/entitlements.plist"
codesign --display --entitlements - --xml "$app" >"$entitlements" 2>/dev/null || true
[[ "$(value application-identifier "$entitlements")" == "$app_identifier" ]] ||
  fail "The signed application identifier is not <Team ID>.$bundle_id for the expected team."
[[ "$(value com.apple.developer.team-identifier "$entitlements")" == "$team" ]] ||
  fail "The signed team identifier is not the expected team."
[[ "$(value get-task-allow "$entitlements")" != "true" ]] ||
  fail "The app is signed with get-task-allow (debugging), which App Store builds must not have."

# --- Provisioning profile ---------------------------------------------------
profile="$unpacked/profile.plist"
profile_ok=no
if [[ -e "$app/embedded.mobileprovision" ]] &&
  security cms -D -i "$app/embedded.mobileprovision" >"$profile" 2>/dev/null; then
  profile_ok=yes
  if [[ "$(value TeamIdentifier:0 "$profile")" != "$team" ]]; then
    fail "The provisioning profile belongs to another team."
    profile_ok=no
  fi
  if [[ "$(value Entitlements:application-identifier "$profile")" != "$app_identifier" ]]; then
    fail "The provisioning profile is not for $bundle_id."
    profile_ok=no
  fi
  if [[ "$(value Entitlements:get-task-allow "$profile")" != "false" ]]; then
    fail "The provisioning profile allows debugging; it is a development profile."
    profile_ok=no
  fi
  if [[ "$(value ProvisionedDevices "$profile")" != "(missing)" ]]; then
    fail "The provisioning profile lists devices; it is a development or ad hoc profile."
    profile_ok=no
  fi
  if [[ "$(value ProvisionsAllDevices "$profile")" != "(missing)" ]]; then
    fail "The provisioning profile provisions all devices; it is an enterprise profile."
    profile_ok=no
  fi
elif [[ -e "$app/embedded.mobileprovision" ]]; then
  fail "The embedded provisioning profile cannot be read."
fi

{
  echo "### IPA check"
  echo "| Check | Result |"
  echo "| --- | --- |"
  echo "| Bundle identifier | $actual_bundle_id |"
  echo "| Version (build) | $actual_version ($actual_build) |"
  echo "| Signed with a distribution certificate | $distribution |"
  echo "| App Store provisioning profile for this team and app | $profile_ok |"
  echo "| App structure complete | $(yes_no "$structure_ok") |"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

if ((failures > 0)); then
  echo "The IPA check found $failures problem(s); nothing was uploaded."
  exit 1
fi
echo "The IPA is an App Store distribution build of $bundle_id $version ($build)."
