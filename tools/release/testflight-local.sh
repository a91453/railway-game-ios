#!/usr/bin/env bash
# Releases the current commit to TestFlight from the owner's Mac, without
# GitHub Actions: internal testing only (testFlightInternalTestingOnly), no
# review, no external testing. The steps and their order follow
# .github/workflows/testflight.yml; see docs/TESTFLIGHT_LOCAL.md for why each
# one differs and what the owner has to press.
#
#   tools/release/testflight-local.sh [--build N] [--archive PATH] [--no-upload]
#
#   --build N        CFBundleVersion; default: <newest successful
#                    testflight.yml run number>.1 (CI makes N or N.2 to N.99
#                    and never N.1, so the two never meet)
#   --archive PATH   reuse an archive this script already made for --build
#   --no-upload      stop after the IPA check (nothing is sent to Apple)
#
# Needs: a clean checkout at origin/main (or a branch on it changing only
# docs/ and tools/release/; anything else is refused), Xcode 27
# or later signed in to the team's Apple ID (Settings -> Accounts), the
# owner's login keychain unlocked, gh signed in (for the team ID, the app ID
# and the last release), and the private assets checkout beside this one for
# the brand. Map packs that changed since the last CI release need an App
# Store Connect API key: ASC_KEY_ID and ASC_ISSUER_ID in the environment and
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8. Without them the
# script stops before uploading anything when a pack changed.
#
# Prints no secret and no certificate name. Leaves the working copy as it
# found it (the brand is put back on exit).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"

build=""
archive=""
upload=true
while (($#)); do
  case "$1" in
    --build) build="${2:?--build needs a number}"; shift 2 ;;
    --archive) archive="${2:?--archive needs a path}"; shift 2 ;;
    --no-upload) upload=false; shift ;;
    *) echo "usage: $0 [--build N] [--archive PATH] [--no-upload]" >&2; exit 64 ;;
  esac
done

step() { printf '\n== %s\n' "$1"; }
die() { echo "error: $1" >&2; exit 1; }

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
  build="$last.1"
fi
[[ "$build" =~ ^[1-9][0-9]{0,3}(\.[0-9]{1,2}){0,2}$ ]] || die "build number $build is not N, N.M or N.M.K."
echo "Commit $(git rev-parse --short HEAD), build $build, Xcode $(xcodebuild -version | head -1)."

work="$HOME/RailwayTestFlight/$build"
mkdir -p "$work"
archive="${archive:-$work/RailwayGame.xcarchive}"

brand_files=(RailwayGameApp/Resources/GameBrand.json
  RailwayGameApp/Resources/en.lproj/InfoPlist.strings
  RailwayGameApp/Resources/zh-Hant.lproj/InfoPlist.strings
  RailwayGameApp/Info.plist)
put_back() { git checkout -q -- "${brand_files[@]}"; }
trap put_back EXIT

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

if [[ ! -d "$archive" ]]; then
  step "Archive (about 35 minutes)"
  # Automatic development signing with the Xcode account: the ad hoc
  # archive CI makes is refused on this Mac ("has entitlements that require
  # signing with a development certificate"). -quiet keeps identity names
  # out of the log.
  xcodebuild archive \
    -project RailwayGameApp/RailwayGame.xcodeproj -scheme RailwayGame \
    -configuration Release -destination "generic/platform=iOS" \
    -archivePath "$archive" -derivedDataPath "$work/DerivedData" \
    -disableAutomaticPackageResolution -allowProvisioningUpdates -quiet \
    CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$team" \
    "CURRENT_PROJECT_VERSION=$build" >"$work/archive.log" 2>&1 || {
    grep -E 'error:|errSec' "$work/archive.log" | sort -u | head -20 >&2
    die "the archive failed (log: $work/archive.log). errSecInternalComponent = the login keychain is locked."
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

auth=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  key="$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
  [[ -f "$key" ]] || die "ASC_KEY_ID is set but $key is missing."
  auth=(-authenticationKeyPath "$key" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

step "Export the IPA (distribution signing, cloud-managed)"
rm -rf "$work/export"
.github/scripts/testflight-retry.sh "Export" xcodebuild -quiet -exportArchive \
  -archivePath "$archive" -exportPath "$work/export" \
  -exportOptionsPlist "$work/ExportOptions.plist" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

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

step "Map packs that changed since the last CI release"
changed="$(GITHUB_TOKEN="$(gh auth token)" GITHUB_REPOSITORY="$repo_slug" GITHUB_RUN_ID=0 \
  python3 -I .github/scripts/testflight-map-packs.py)"
if [[ -n "$changed" ]]; then
  ((${#auth[@]})) || die "map packs changed ($changed) and uploading them needs the API key (ASC_KEY_ID, ASC_ISSUER_ID); nothing was uploaded."
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
  -exportOptionsPlist "$work/UploadOptions.plist" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

echo
echo "Uploaded $version ($build) for internal TestFlight testing from $(git rev-parse --short HEAD)."
echo "It shows in TestFlight once App Store Connect has processed it (about 10 to 30 minutes):"
echo "https://appstoreconnect.apple.com/apps/$app_id/testflight/ios"
echo "Archive and logs: $work (delete it when the build is out)."
