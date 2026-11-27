#!/usr/bin/env bash
# Releases the current commit to TestFlight from the owner's Mac, without
# GitHub Actions: internal testing only (testFlightInternalTestingOnly), no
# review, no external testing. The steps and their order follow
# .github/workflows/testflight.yml; see docs/TESTFLIGHT_LOCAL.md for why each
# one differs and what the owner has to press.
#
#   tools/release/testflight-local.sh [--build N] [--carry-map-packs yes|no]
#                                     [--archive PATH] [--no-upload] [--skip-packs]
#
#   --build N        CFBundleVersion; default: <newest successful
#                    testflight.yml run number>.1, then .1.1, .1.2 for more
#                    Mac releases before the next CI one (CI makes N or N.2
#                    to N.99 and never N.1, so the two never meet)
#   --carry-map-packs yes|no
#                    no (default, as CI's): pack.json only, so the packs come
#                    from App Store Connect; yes: the app carries every map
#                    pack whole (testflight.yml's carry_map_packs)
#   --archive PATH   reuse an archive this script already made for --build
#   --no-upload      stop after the IPA check (nothing is sent to Apple)
#   --skip-packs     do not upload map packs (an earlier run already did)
#
# Needs: a clean checkout at origin/main (or a branch on it changing only
# docs/ and tools/release/; anything else is refused), Xcode 27 or later, gh
# signed in (for the team ID, the app ID and the last release), the private
# assets checkout beside this one for the brand, and an App Store Connect
# API key with the Admin role (App Manager cannot use the cloud-managed
# distribution certificate): ~/.appstoreconnect/private_keys/AuthKey_<id>.p8
# and ~/.appstoreconnect/local-release.env with ASC_KEY_ID, ASC_ISSUER_ID
# and RELEASE_KEYCHAIN_PASSWORD (written on the first run), never in a repo.
#
# Signing uses its own keychain, ~/.appstoreconnect/release.keychain-db,
# made on the first run; Xcode puts the development certificate it creates
# there. While the archive, export and upload run (minutes when the build
# is cached, about 35 when it is not), that keychain is the user's only and
# default keychain: with the login keychain in the list Xcode refuses the
# ad hoc archive CI makes and signs with the login keychain's certificate,
# which a remote session cannot unlock. The keychain list and default are
# put back on exit, also after a failure or Ctrl-C.
#
# Prints no secret and no certificate name. Leaves the working copy as it
# found it (the brand is put back on exit).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"

build=""
archive=""
upload=true
packs=true
carry=no
while (($#)); do
  case "$1" in
    --build) build="${2:?--build needs a number}"; shift 2 ;;
    --archive) archive="${2:?--archive needs a path}"; shift 2 ;;
    --no-upload) upload=false; shift ;;
    --skip-packs) packs=false; shift ;;
    --carry-map-packs) carry="${2:?--carry-map-packs needs yes or no}"; shift 2 ;;
    *) echo "usage: $0 [--build N] [--carry-map-packs yes|no] [--archive PATH] [--no-upload] [--skip-packs]" >&2; exit 64 ;;
  esac
done

step() { printf '\n== %s\n' "$1"; }
die() { echo "error: $1" >&2; exit 1; }

[[ "$carry" == yes || "$carry" == no ]] || die "--carry-map-packs takes yes or no, not $carry."
# The Mac's last release ({"build", "commit"}): map packs and What to Test
# compare with it when it is newer than CI's (tools/release/local_release.py).
record="$HOME/RailwayTestFlight/last-release.json"
local_release() { python3 -I tools/release/local_release.py "$@" --record "$record"; }

step "Checks"
git fetch -q origin main
[[ -z "$(git status --porcelain)" ]] || die "the working copy has changes; release from a clean checkout."
# origin/main itself, or a branch on it that changes only docs and this
# script (the app built is then origin/main's).
git merge-base --is-ancestor origin/main HEAD ||
  die "HEAD does not contain origin/main ($(git rev-parse --short origin/main)); check out origin/main first."
extra="$(git diff --name-only origin/main HEAD | grep -vE '^(docs/|tools/release/)' || true)"
[[ -z "$extra" ]] || die "HEAD changes files beyond origin/main: $extra"
major="$(xcodebuild -version | awk 'NR == 1 { split($2, v, "."); print v[1] }')"
((major >= 27)) || die "App Store Connect needs Xcode 27 or later; this is Xcode $major."
team="$(gh variable get APPLE_TEAM_ID --env testflight)"
app_id="$(gh variable get ASC_APP_ID --env testflight)"
repo_slug="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
if [[ -z "$build" ]]; then
  last="$(gh run list --workflow testflight.yml --branch main --status success -L 1 --json number -q '.[0].number')"
  [[ -n "$last" ]] || die "no successful testflight.yml run found; pass --build."
  build="$(local_release next-build --ci-build "$last")"
fi
[[ "$build" =~ ^[1-9][0-9]{0,3}(\.[0-9]{1,2}){0,2}$ ]] || die "build number $build is not N, N.M or N.M.K."
echo "Commit $(git rev-parse --short HEAD), build $build, map packs carried: $carry, Xcode $(xcodebuild -version | head -1)."
carry_args=()
if [[ "$carry" == yes ]]; then carry_args=(CARRY_MAP_PACKS=YES); else carry_args=(CARRY_MAP_PACKS=NO); fi

work="$HOME/RailwayTestFlight/$build"
mkdir -p "$work"
archive="${archive:-$work/RailwayGame.xcarchive}"

env_file="$HOME/.appstoreconnect/local-release.env"
[[ -f "$env_file" ]] || die "$env_file is missing (ASC_KEY_ID, ASC_ISSUER_ID; docs/TESTFLIGHT_LOCAL.md)."
# shellcheck disable=SC1090
source "$env_file"
[[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] || die "$env_file needs ASC_KEY_ID and ASC_ISSUER_ID."
key="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
[[ -f "$key" ]] || die "$key is missing."
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

brand_files=(RailwayGameApp/Resources/GameBrand.json
  RailwayGameApp/Resources/en.lproj/InfoPlist.strings
  RailwayGameApp/Resources/zh-Hant.lproj/InfoPlist.strings
  RailwayGameApp/Info.plist)
keychain="$HOME/.appstoreconnect/release.keychain-db"
saved_default=""
saved_list=()
use_release_keychain() {
  saved_default="$(security default-keychain -d user | sed -e 's/^ *"//' -e 's/"$//')"
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && saved_list+=("$line")
  done < <(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')
  if [[ ! -f "$keychain" ]]; then
    RELEASE_KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
    security create-keychain -p "$RELEASE_KEYCHAIN_PASSWORD" "$keychain"
    (umask 077; printf 'RELEASE_KEYCHAIN_PASSWORD=%s\n' "$RELEASE_KEYCHAIN_PASSWORD" >>"$env_file")
  fi
  security unlock-keychain -p "${RELEASE_KEYCHAIN_PASSWORD:?RELEASE_KEYCHAIN_PASSWORD is not in $env_file}" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security list-keychains -d user -s "$keychain"
  security default-keychain -d user -s "$keychain"
  echo "The release keychain is the only keychain until this script ends."
}
put_back() {
  set +e
  git checkout -q -- "${brand_files[@]}"
  if [[ -n "$saved_default" ]]; then
    security list-keychains -d user -s ${saved_list[@]+"${saved_list[@]}"}
    security default-keychain -d user -s "$saved_default"
    security lock-keychain "$keychain"
    echo "Keychain list and default keychain put back."
  fi
}
trap put_back EXIT INT TERM

step "Brand"
brand=""
for candidate in ../railway-assets-private-2 ../railway-assets-private; do
  if [[ -f "$candidate/branding/game-brand.json" ]]; then
    brand="$candidate/branding/game-brand.json"
    break
  fi
done
[[ -n "$brand" ]] || die "no branding/game-brand.json in ../railway-assets-private-2 or ../railway-assets-private."
python3 -I tools/brand/apply_brand.py "$brand" >/dev/null
echo "Applied the brand from $(dirname "$(dirname "$brand")")."

use_release_keychain

if [[ ! -d "$archive" ]]; then
  step "Archive"
  # testflight-archive.sh's "automatic" mode: development signing with the
  # API key, the certificate in the release keychain. -quiet keeps identity
  # names out of the log.
  xcodebuild archive \
    -project RailwayGameApp/RailwayGame.xcodeproj -scheme RailwayGame \
    -configuration Release -destination "generic/platform=iOS" \
    -archivePath "$archive" -derivedDataPath "$work/DerivedData" \
    -disableAutomaticPackageResolution -quiet "${auth[@]}" \
    CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$team" ${carry_args[@]+"${carry_args[@]}"} \
    "CURRENT_PROJECT_VERSION=$build" >"$work/archive.log" 2>&1 || {
    grep -E 'error:|errSec' "$work/archive.log" | sort -u | head -20 >&2
    die "the archive failed (log: $work/archive.log)."
  }
fi
archived="$archive/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$archived")"
version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archived")"
archived_build="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archived")"
[[ "$archived_build" == "$build" ]] || die "the archive is build $archived_build, not $build."

write_options() {
  cat >"$2" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>$1</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$team</string>
	<key>testFlightInternalTestingOnly</key>
	<true/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
}
write_options export "$work/ExportOptions.plist"
write_options upload "$work/UploadOptions.plist"

step "Export the IPA (distribution signing, cloud-managed)"
rm -rf "$work/export"
.github/scripts/testflight-retry.sh "Export" xcodebuild -quiet -exportArchive \
  -archivePath "$archive" -exportPath "$work/export" \
  -exportOptionsPlist "$work/ExportOptions.plist" "${auth[@]}"

step "Check the IPA"
shopt -s nullglob
ipas=("$work/export"/*.ipa)
((${#ipas[@]} == 1)) || die "expected one IPA in $work/export, found ${#ipas[@]}."
EXPECTED_BUNDLE_ID="$bundle_id" EXPECTED_VERSION="$version" EXPECTED_BUILD="$build" \
  EXPECTED_TEAM_ID="$team" .github/scripts/testflight-verify-ipa.sh "${ipas[0]}"

if [[ "$upload" != true ]]; then
  echo "Stopped before uploading (--no-upload). Archive: $archive"
  exit 0
fi

step "Map packs that changed since the last release (CI's or this Mac's)"
changed=""
[[ "$packs" == true ]] || echo "Skipped (--skip-packs)."
[[ "$packs" != true ]] || changed="$(GITHUB_TOKEN="$(gh auth token)" GITHUB_REPOSITORY="$repo_slug" GITHUB_RUN_ID=0 \
  local_release packs)"
if [[ -n "$changed" ]]; then
  # shellcheck disable=SC2086 # one ID a word
  tools/asset-packs/package.sh "$work/asset-packs" $changed
  for id in $changed; do
    xcrun altool --upload-asset-pack "$work/asset-packs/$id.aar" \
      --apple-id "$app_id" --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID"
    echo "Uploaded a new version of $id."
  done
else
  echo "No map pack changed."
fi

step "Upload the build (internal TestFlight only)"
rm -rf "$work/upload"
.github/scripts/testflight-retry.sh "Upload" xcodebuild -quiet -exportArchive \
  -archivePath "$archive" -exportPath "$work/upload" \
  -exportOptionsPlist "$work/UploadOptions.plist" "${auth[@]}"

echo "Uploaded $version ($build) for internal TestFlight testing from $(git rev-parse --short HEAD)."
# What to Test compares with the release before this one, so it is written
# before this one is recorded.
GITHUB_TOKEN="$(gh auth token)" GITHUB_REPOSITORY="$repo_slug" GITHUB_RUN_ID=0 \
  local_release whats-new >"$work/whats-new.txt" || true
# Run from a docs/tools branch on origin/main: leave its own commits out.
while IFS= read -r subject; do
  grep -vxF -- "- $subject" "$work/whats-new.txt" >"$work/whats-new.tmp" || true
  mv "$work/whats-new.tmp" "$work/whats-new.txt"
done < <(git log --format=%s origin/main..HEAD)
local_release record --build "$build" --commit "$(git rev-parse origin/main)"
put_back
saved_default=""

# testflight.yml's processing job: wait for App Store Connect, then fill What
# to Test with the pull requests merged since the last CI release.
step "Wait for App Store Connect processing, fill What to Test"
ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" ASC_PRIVATE_KEY="$(cat "$key")" \
  ASC_APP_ID="$app_id" BUILD_NUMBER="$build" APP_VERSION="$version" \
  GITHUB_STEP_SUMMARY="$work/processing-summary.md" \
  python3 -I .github/scripts/testflight-processing.py --whats-new "$work/whats-new.txt"

echo
echo "https://appstoreconnect.apple.com/apps/$app_id/testflight/ios"
echo "Archive and logs: $work (delete it when the build is out)."
