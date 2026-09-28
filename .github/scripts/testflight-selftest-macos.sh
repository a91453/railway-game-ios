#!/usr/bin/env bash
# Tests the macOS side of the TestFlight release on a real macOS runner with
# no Apple account and fake values only. Nothing is signed with an Apple
# certificate and nothing is uploaded.
#
#   testflight-selftest-macos.sh signing   temporary keychain and API key file:
#                                          setup with a fake key, a failing
#                                          step, cleanup, restore, repeat
#   testflight-selftest-macos.sh tools     the archive and export options the
#                                          dry run produced, and the xcodebuild
#                                          and altool options the release uses
#   testflight-selftest-macos.sh ipa       testflight-verify-ipa.sh against
#                                          synthetic IPAs signed with throwaway
#                                          self-signed certificates
#
# Used by testflight-checks.yml.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
marker="FAKE_PRIVATE_SECRET_DO_NOT_PRINT"
fake_key_id="FAKEKEY001"
failures=0
fail() {
  echo "::error title=TestFlight self-test::$1"
  failures=$((failures + 1))
}
finish() {
  if ((failures > 0)); then
    echo "$failures check(s) failed."
    exit 1
  fi
  echo "All checks passed."
}
user_keychains() { security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//'; }
default_keychain() { security default-keychain -d user | sed -e 's/^ *"//' -e 's/"$//'; }

test_signing() {
  local tmp runner_temp env_file log before_list before_default
  tmp="$(mktemp -d)"
  runner_temp="$tmp/runner"
  env_file="$tmp/github_env"
  log="$tmp/log"
  mkdir -p "$runner_temp"
  before_list="$(user_keychains)"
  before_default="$(default_keychain)"
  signing() {
    RUNNER_TEMP="$runner_temp" GITHUB_ENV="$env_file" \
      ASC_KEY_ID="$fake_key_id" ASC_PRIVATE_KEY=$'\r\n-----BEGIN PRIVATE KEY-----\r\n'"$marker"$'\r\n-----END PRIVATE KEY-----\r\n' \
      "$here/testflight-signing.sh" "$@" >>"$log" 2>&1
  }

  signing setup || fail "setup failed"
  local keychain="$runner_temp/testflight-state/signing.keychain-db"
  [[ "$(default_keychain)" == "$keychain" ]] || fail "the temporary keychain is not the default"
  user_keychains | grep -qxF "$keychain" || fail "the temporary keychain is not in the search list"
  security show-keychain-info "$keychain" >/dev/null 2>&1 || fail "the temporary keychain is locked"
  local key_path
  key_path="$(sed -n 's/^ASC_KEY_PATH=//p' "$env_file")"
  [[ "$key_path" == */AuthKey_$fake_key_id.p8 ]] || fail "unexpected key file name"
  [[ "$(sed -n 's/^API_PRIVATE_KEYS_DIR=//p' "$env_file")" == "$(dirname "$key_path")" ]] ||
    fail "API_PRIVATE_KEYS_DIR does not hold the key file"
  [[ "$(stat -f %Lp "$key_path")" == 600 ]] || fail "the key file is not mode 600"
  ! grep -q $'\r' "$key_path" || fail "the key file keeps CR line endings"
  [[ "$(head -n 1 "$key_path")" == "-----BEGIN PRIVATE KEY-----" ]] || fail "the key file does not start with the key"
  sed -n 's/^ARCHIVE_PATH=//p' "$env_file" | grep -q '/testflight/RailwayGame.xcarchive$' ||
    fail "ARCHIVE_PATH is not exported"

  signing setup && fail "a second setup without cleanup was accepted"

  # A release step fails after setup; cleanup must still restore everything.
  (
    set -e
    false
  ) || true
  signing cleanup || fail "cleanup failed"
  [[ "$(user_keychains)" == "$before_list" ]] || fail "the keychain search list was not restored"
  [[ "$(default_keychain)" == "$before_default" ]] || fail "the default keychain was not restored"
  [[ ! -e "$keychain" ]] || fail "the temporary keychain was not deleted"
  [[ ! -e "$runner_temp/testflight-state" && ! -e "$runner_temp/testflight" ]] ||
    fail "signing files were left behind"
  signing cleanup || fail "a second cleanup failed"
  [[ "$(user_keychains)" == "$before_list" ]] || fail "a second cleanup changed the search list"

  # Setup without a key (the dry run) writes no key file.
  : >"$env_file"
  RUNNER_TEMP="$runner_temp" GITHUB_ENV="$env_file" "$here/testflight-signing.sh" setup >>"$log" 2>&1 ||
    fail "setup without a key failed"
  ! grep -q '^ASC_KEY_PATH=' "$env_file" || fail "setup without a key exported a key path"
  signing cleanup || fail "cleanup after a keyless setup failed"

  if grep -qF -e "$marker" -e "BEGIN PRIVATE KEY" "$log"; then
    fail "the signing script printed the private key"
  fi
  rm -rf "$tmp"
  finish
}

test_tools() {
  local archive="${ARCHIVE_PATH:?run the unsigned dry-run archive first}"
  local options="${EXPORT_OPTIONS:?run the unsigned dry-run archive first}"
  [[ -d "$archive/Products/Applications/RailwayGame.app" ]] || fail "the archive has no RailwayGame.app"
  if ! /usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$archive/Info.plist" >/dev/null 2>&1; then
    fail "the archive's Info.plist has no ApplicationProperties"
  fi

  plutil -lint "$options" || fail "the export options are not a valid property list"
  local key
  for key in destination manageAppVersionAndBuildNumber method signingStyle uploadSymbols; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$options" >/dev/null 2>&1 || fail "the export options have no $key"
  done
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :method' "$options")" == "app-store-connect" ]] ||
    fail "the export method is not app-store-connect"

  # What this Xcode documents: the export option keys, the method, and the
  # xcodebuild options the release uses.
  local help
  help="$(xcodebuild -help 2>&1)"
  for key in destination manageAppVersionAndBuildNumber method signingStyle teamID uploadSymbols; do
    grep -Eq "^[[:space:]]+$key : " <<<"$help" || fail "xcodebuild -help does not document the export option $key"
  done
  grep -q 'app-store-connect' <<<"$help" || fail "xcodebuild -help does not offer the app-store-connect method"
  for key in -exportArchive -allowProvisioningUpdates -authenticationKeyPath -authenticationKeyID \
    -authenticationKeyIssuerID -disableAutomaticPackageResolution; do
    grep -qe "$key" <<<"$help" || fail "xcodebuild -help does not document $key"
  done

  # What this Xcode's altool offers for the upload step.
  xcrun --find altool >/dev/null || fail "xcrun cannot find altool"
  local altool_help
  altool_help="$(xcrun altool --help 2>&1 || true)"
  for key in --upload-package --apiKey --apiIssuer --apple-id --bundle-id --bundle-version \
    --bundle-short-version-string API_PRIVATE_KEYS_DIR; do
    grep -qe "$key" <<<"$altool_help" || fail "altool --help does not mention $key"
  done
  echo "$(xcodebuild -version | head -n 1): export options, xcodebuild and altool options checked."
  finish
}

test_ipa() {
  local tmp kc kc_password saved
  tmp="$(mktemp -d)"
  kc="$tmp/fixtures.keychain-db"
  kc_password="$(openssl rand -hex 16)"
  saved="$(user_keychains)"
  restore() {
    local list=()
    while IFS= read -r line; do [[ -n "$line" ]] && list+=("$line"); done <<<"$saved"
    security list-keychains -d user -s ${list[@]+"${list[@]}"}
    security delete-keychain "$kc" 2>/dev/null || true
    rm -rf "$tmp"
  }
  trap restore EXIT

  security create-keychain -p "$kc_password" "$kc"
  security unlock-keychain -p "$kc_password" "$kc"
  local list=()
  while IFS= read -r line; do [[ -n "$line" ]] && list+=("$line"); done <<<"$saved"
  security list-keychains -d user -s "$kc" ${list[@]+"${list[@]}"}

  # Throwaway self-signed code-signing identities, named like the two kinds
  # of Apple certificate the check tells apart. They exist only in this
  # keychain and sign nothing but the fixtures below.
  local team="FAKETEAM01" bundle="io.github.a91453.RailwayGame"
  make_identity() {
    local name="$1" cn="$2"
    cat >"$tmp/$name.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $cn
OU = $team
O = Dry Run Fixture
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    openssl req -x509 -new -newkey rsa:2048 -nodes -days 2 -config "$tmp/$name.cnf" -extensions ext \
      -keyout "$tmp/$name.key" -out "$tmp/$name.pem"
    openssl pkcs12 -export -inkey "$tmp/$name.key" -in "$tmp/$name.pem" -out "$tmp/$name.p12" \
      -passout pass:fixture -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
    security import "$tmp/$name.p12" -k "$kc" -P fixture -T /usr/bin/codesign >/dev/null
    openssl x509 -noout -fingerprint -sha1 -in "$tmp/$name.pem" | sed -e 's/.*=//' -e 's/://g' >"$tmp/$name.sha1"
  }
  make_identity distribution "Apple Distribution: Dry Run Fixture ($team)"
  make_identity development "Apple Development: Dry Run Fixture ($team)"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kc_password" "$kc" >/dev/null

  # make_ipa <name> <identity> <build> <profile get-task-allow> <extra profile XML> [no-profile]
  make_ipa() {
    local name="$1" identity="$2" build="$3" profile_debug="$4" profile_extra="$5" without_profile="${6:-}"
    local root="$tmp/$name" app="$tmp/$name/Payload/RailwayGame.app"
    mkdir -p "$app"
    cp /usr/bin/true "$app/RailwayGame"
    printf 'fixture' >"$app/Assets.car"
    cat >"$app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RailwayGame</string>
<key>CFBundleIdentifier</key><string>$bundle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>$build</string>
</dict></plist>
EOF
    cat >"$root/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$team.$bundle</string>
<key>com.apple.developer.team-identifier</key><string>$team</string>
<key>get-task-allow</key><false/>
</dict></plist>
EOF
    if [[ -z "$without_profile" ]]; then
      cat >"$root/profile.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Name</key><string>Dry Run Fixture</string>
<key>TeamIdentifier</key><array><string>$team</string></array>
<key>Entitlements</key><dict>
<key>application-identifier</key><string>$team.$bundle</string>
<key>get-task-allow</key><$profile_debug/>
</dict>
$profile_extra
</dict></plist>
EOF
      openssl smime -sign -binary -nodetach -outform DER -in "$root/profile.plist" \
        -signer "$tmp/distribution.pem" -inkey "$tmp/distribution.key" -out "$app/embedded.mobileprovision"
    fi
    codesign --force --sign "$(cat "$tmp/$identity.sha1")" --keychain "$kc" --timestamp=none \
      --entitlements "$root/entitlements.plist" "$app" 2>"$root/codesign.log" ||
      { fail "could not sign the $name fixture: $(cat "$root/codesign.log")"; return; }
    (cd "$root" && zip -qry "$tmp/$name.ipa" Payload)
  }
  local devices='<key>ProvisionedDevices</key><array><string>00008030-00000000FAKEFAKE</string></array>'
  make_ipa valid distribution 7.2 false ""
  make_ipa wrong-build distribution 7.1 false ""
  make_ipa development-profile distribution 7.2 true ""
  make_ipa device-list distribution 7.2 false "$devices"
  make_ipa missing-profile distribution 7.2 false "" no-profile
  make_ipa development-signing development 7.2 false ""

  # check <fixture> <expected exit> [error text]
  check() {
    local name="$1" expected="$2" text="${3:-}" status=0
    EXPECTED_BUNDLE_ID="$bundle" EXPECTED_VERSION=0.1.0 EXPECTED_BUILD=7.2 EXPECTED_TEAM_ID="$team" \
      GITHUB_STEP_SUMMARY=/dev/null "$here/testflight-verify-ipa.sh" "$tmp/$name.ipa" >"$tmp/$name.log" 2>&1 ||
      status=$?
    if [[ "$status" -ne "$expected" ]]; then
      fail "$name: the IPA check exited $status, expected $expected"
      sed 's/^/    /' "$tmp/$name.log"
    elif [[ -n "$text" ]] && ! grep -qF -- "$text" "$tmp/$name.log"; then
      fail "$name: no error containing '$text'"
      sed 's/^/    /' "$tmp/$name.log"
    else
      echo "$name: exit $status as expected"
    fi
    if grep -q "Dry Run Fixture" "$tmp/$name.log"; then
      fail "$name: the IPA check printed a certificate or profile name"
    fi
  }
  check valid 0
  check wrong-build 1 "The build number is 7.1, not 7.2."
  check development-profile 1 "it is a development profile"
  check device-list 1 "lists devices"
  check missing-profile 1 "The app has no embedded.mobileprovision."
  check development-signing 1 "signed with a development certificate"
  finish
}

case "${1:-}" in
  signing) test_signing ;;
  tools) test_tools ;;
  ipa) test_ipa ;;
  *)
    echo "usage: $0 signing|tools|ipa" >&2
    exit 64
    ;;
esac
