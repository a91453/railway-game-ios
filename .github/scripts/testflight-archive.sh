#!/usr/bin/env bash
# Archives the committed Xcode project for App Store distribution and writes
# the export options: one to export the signed IPA that is checked, one to
# upload the same archive to App Store Connect.
#
#   testflight-archive.sh adhoc [internal|external]
#                                     the release default: sign the archive
#                                     ad hoc ("-") so no development
#                                     certificate or profile is needed (a
#                                     team with no registered device cannot
#                                     get a development profile). The IPA is
#                                     not ad hoc: the App Store distribution
#                                     signature and profile are applied at
#                                     export, and testflight-verify-ipa.sh
#                                     checks them
#   testflight-archive.sh automatic [internal|external]
#                                     release alternative: automatic
#                                     development signing for the real team,
#                                     with the App Store Connect API key and
#                                     -allowProvisioningUpdates, as Apple
#                                     documents for headless xcodebuild; needs
#                                     a development profile, so it fails for
#                                     a team with no registered device
#   testflight-archive.sh unsigned [internal|external]
#                                     dry run: no team, no key, no signing
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
#   CARRY_MAP_PACKS_INPUT             optional: yes (default) or no, whether
#                                     the app carries the map packs whole
#   TESTFLIGHT_OPTIONS_ONLY           dry run only: 1 writes the options for
#                                     the archive already made, no archive
# The optional second argument selects TestFlight scope and defaults to
# "internal" for backward compatibility. External mode deliberately omits
# Apple's testFlightInternalTestingOnly export option.
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   automatic
set -euo pipefail

mode="${1:-}"
testing_scope="${2:-internal}"
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
    echo "usage: $0 automatic|adhoc|unsigned [internal|external]" >&2
    exit 64
    ;;
esac
case "$testing_scope" in
  internal|external) ;;
  *)
    echo "usage: $0 automatic|adhoc|unsigned [internal|external]" >&2
    exit 64
    ;;
esac
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  args+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi
# MAP-PACK-COPY: testflight.yml's carry_map_packs; "no" builds the app with
# each city's pack.json only (project.yml's CARRY_MAP_PACKS, default YES).
case "${CARRY_MAP_PACKS_INPUT:-yes}" in
  yes) ;;
  no) args+=(CARRY_MAP_PACKS=NO) ;;
  *)
    echo "CARRY_MAP_PACKS_INPUT must be yes or no, not ${CARRY_MAP_PACKS_INPUT}." >&2
    exit 64
    ;;
esac

# testflight-checks.yml's dry run: the archive does not depend on the
# TestFlight scope, only the options below do, so its second scope rewrites
# the options for the archive it already made instead of archiving again
# (half an hour; decision 1016). The release never sets this.
if [[ "${TESTFLIGHT_OPTIONS_ONLY:-}" == 1 ]]; then
  if [[ ! -d "$archive_path" ]]; then
    echo "::error::TESTFLIGHT_OPTIONS_ONLY=1 needs the archive that was already made at $archive_path." >&2
    exit 1
  fi
  echo "Options only: the archive at $archive_path is kept."
else
  xcodebuild "${args[@]}"
fi

# App Store Connect distribution, signed automatically by xcodebuild at
# export (cloud-managed distribution certificate when no local one exists).
# "export" writes the IPA that is checked; "upload" re-exports the same
# archive with the same signing options and sends it to App Store Connect.
# The build number comes from the archive; Xcode must not change it. Internal
# mode adds Apple's internal-only marker; external mode omits it so App Store
# Connect can submit the build to Beta App Review and external testing.
team_entry=""
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
  team_entry="	<key>teamID</key>
	<string>$APPLE_TEAM_ID</string>"
fi
internal_testing_entry=""
if [[ "$testing_scope" == internal ]]; then
  internal_testing_entry="	<key>testFlightInternalTestingOnly</key>
	<true/>"
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
$internal_testing_entry
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
}
write_options export "$export_options"
write_options upload "$upload_options"
echo "Archive ($mode, $testing_scope TestFlight) and export and upload options written."
