#!/bin/bash
# Build the iOS app for this Mac ("Designed for iPad", Apple silicon only) and
# open it. docs/MAC_LOCAL_SETUP.md, section 8, says what this is good for and
# what it cannot show.
#
#   tools/mac-run/run_on_mac.sh            # Debug
#   tools/mac-run/run_on_mac.sh Release
#
# The Team ID never goes into a file: it comes from TEAM_ID in the
# environment, or else from the Apple Development certificate in the keychain.
# The first build on a Mac that is not yet a registered device of the
# developer account fails at signing; run it once with REGISTER_DEVICE=1,
# which adds the Mac to the account's device list (the owner's decision).
set -euo pipefail

CONFIGURATION="${1:-Debug}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DERIVED="${DERIVED:-$HOME/Library/Developer/RailwayGameDerived-mac}"
BUNDLE_ID="io.github.a91453.RailwayGame"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This needs a Mac with Apple silicon." >&2
  exit 1
fi

if [[ -z "${TEAM_ID:-}" ]]; then
  TEAM_ID="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)"
fi
if [[ -z "$TEAM_ID" ]]; then
  echo "No Team ID: export TEAM_ID, or sign in to Xcode so the keychain has an Apple Development certificate." >&2
  exit 1
fi

REGISTER=()
if [[ "${REGISTER_DEVICE:-0}" == "1" ]]; then
  REGISTER=(-allowProvisioningDeviceRegistration)
fi

echo "Building ($CONFIGURATION)..."
xcodebuild build \
  -project "$REPO/RailwayGameApp/RailwayGame.xcodeproj" \
  -scheme RailwayGame \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,variant=Designed for iPad" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  ${REGISTER[@]+"${REGISTER[@]}"} \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -quiet

BUILT="$DERIVED/Build/Products/$CONFIGURATION-iphoneos/RailwayGame.app"
if [[ ! -d "$BUILT" ]]; then
  echo "Built app not found at $BUILT" >&2
  exit 1
fi

# An iOS bundle does not open on its own ("incorrect executable format").
# macOS opens it from inside an outer bundle of this shape, the one the Mac
# App Store gives an iPad app it installs.
WRAPPER="$DERIVED/MacRun/RailwayGame.app"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "/Wrapper/RailwayGame.app/RailwayGame" >/dev/null || break
  sleep 0.5
done
rm -rf "$DERIVED/MacRun"
mkdir -p "$WRAPPER/Wrapper"
cp -R "$BUILT" "$WRAPPER/Wrapper/"
ln -s "Wrapper/RailwayGame.app" "$WRAPPER/WrappedBundle"

open "$WRAPPER"
echo "Opened $WRAPPER"
