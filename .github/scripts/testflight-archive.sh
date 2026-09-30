#!/usr/bin/env bash
# Archives the committed Xcode project for App Store distribution and writes
# the export options: one to export the signed IPA that is checked, one to
# upload the same archive to App Store Connect.
#
#   testflight-archive.sh adhoc       the release default: sign the archive
#                                     ad hoc ("-") so no development
#                                     certificate or profile is needed (a
#                                     team with no registered device cannot
#                                     get a development profile). The IPA is
#                                     not ad hoc: the App Store distribution
#                                     signature and profile are applied at
#                                     export, and testflight-verify-ipa.sh
#                                     checks them
#   testflight-archive.sh automatic   release alternative: automatic
#                                     development signing for the real team,
#                                     with the App Store Connect API key and
#                                     -allowProvisioningUpdates, as Apple
#                                     documents for headless xcodebuild; needs
#                                     a development profile, so it fails for
#                                     a team with no registered device
#   testflight-archive.sh unsigned    dry run: no team, no key, no signing
#
# Always: Release configuration, generic iOS device, the committed project
# and shared scheme (never regenerated here), and no automatic package
# resolution (see ios-build.yml).
#
# macOS only; run after `testflight-signing.sh setup`. Inputs (environment):
#   ARCHIVE_PATH, EXPORT_OPTIONS,
#   UPLOAD_OPTIONS                    from testflight-signing.sh
#   APPLE_TEAM_ID                     adhoc, automatic
#   BUILD_NUMBER                      optional: CFBundleVersion of this build
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   automatic
set -euo pipefail

mode="${1:-}"
archive_path="${ARCHIVE_PATH:?ARCHIVE_PATH is not set; run testflight-signing.sh setup first}"
export_options="${EXPORT_OPTIONS:?EXPORT_OPTIONS is not set; run testflight-signing.sh setup first}"
upload_options="${UPLOAD_OPTIONS:?UPLOAD_OPTIONS is not set; run testflight-signing.sh setup first}"

args=(
  archive
  -project RailwayGameApp/RailwayGame.xcodeproj
  -scheme RailwayGame
  -configuration Release
  -destination "generic/platform=iOS"
  -archivePath "$archive_path"
  -derivedDataPath "${RUNNER_TEMP:?RUNNER_TEMP is not set}/DerivedData"
  -disableAutomaticPackageResolution
)
# Release modes run with -quiet: a verbose signed build prints each code
# signing identity, whose name is the account holder's, into public logs.
# Errors and warnings are still printed.
case "$mode" in
  automatic)
    args+=(
      -quiet
      -allowProvisioningUpdates
      -authenticationKeyPath "${ASC_KEY_PATH:?ASC_KEY_PATH is not set}"
      -authenticationKeyID "${ASC_KEY_ID:?ASC_KEY_ID is not set}"
      -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set}"
      CODE_SIGN_STYLE=Automatic
      "DEVELOPMENT_TEAM=${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
    )
    ;;
  adhoc)
    args+=(
      -quiet
      CODE_SIGN_STYLE=Automatic
      CODE_SIGN_IDENTITY=-
      AD_HOC_CODE_SIGNING_ALLOWED=YES
      "DEVELOPMENT_TEAM=${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
    )
    ;;
  unsigned)
    args+=(CODE_SIGNING_ALLOWED=NO)
    ;;
  *)
    echo "usage: $0 automatic|adhoc|unsigned" >&2
    exit 64
    ;;
esac
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  args+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

xcodebuild "${args[@]}"

# App Store Connect distribution, signed automatically by xcodebuild at
# export (cloud-managed distribution certificate when no local one exists).
# "export" writes the IPA that is checked; "upload" re-exports the same
# archive with the same signing options and sends it to App Store Connect.
# Both paths are restricted to internal TestFlight. The build number comes
# from the archive; Xcode must not change it.
team_entry=""
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
  team_entry="	<key>teamID</key>
	<string>$APPLE_TEAM_ID</string>"
fi
write_options() {
  local destination="$1" path="$2"
  cat >"$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>$destination</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
$team_entry
	<key>testFlightInternalTestingOnly</key>
	<true/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
}
write_options export "$export_options"
write_options upload "$upload_options"
echo "Archive ($mode) and export and upload options written."
