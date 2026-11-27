#!/usr/bin/env bash
# Checks a built RailwayGame.app carries all of the game's languages
# (ARCHITECTURE decision 257; Japanese since decision 1034): English,
# Traditional Chinese and Japanese, each with its InfoPlist.strings, and
# the String Catalog's Chinese and Japanese text. iOS offers
# an app only the languages its bundle has, so a lost .lproj would leave
# the player one language and an empty language row in Settings.
#
# Usage: check-app-localizations.sh <path to RailwayGame.app>
set -euo pipefail

app="${1:?usage: check-app-localizations.sh <app>}"
failed=false
fail() { echo "::error::$1"; failed=true; }

echo "Localizations in $(basename "$app"):"
found=false
for dir in "$app"/*.lproj; do
  [[ -d "$dir" ]] || continue
  found=true
  # shellcheck disable=SC2012 # the folder names are .lproj names, no odd characters
  echo "  $(basename "$dir"): $(cd "$dir" && ls | paste -sd' ' -)"
done
[[ "$found" == true ]] || echo "  (none)"

for language in en zh-Hant ja; do
  [[ -f "$app/$language.lproj/InfoPlist.strings" ]] \
    || fail "The app has no $language.lproj/InfoPlist.strings: iOS would not offer $language."
done
# The String Catalog compiles to one Localizable.strings per translated
# language; English, its source, may need none.
for language in zh-Hant ja; do
  [[ -f "$app/$language.lproj/Localizable.strings" ]] \
    || fail "The app has no $language.lproj/Localizable.strings: the String Catalog's $language text is missing."
done

[[ "$failed" == false ]]
echo "All three languages are in the app."
