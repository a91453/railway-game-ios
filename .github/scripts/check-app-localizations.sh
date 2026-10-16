#!/usr/bin/env bash
# Checks a built RailwayGame.app carries both of the game's languages
# (ARCHITECTURE decision 257): English and Traditional Chinese, each with
# its InfoPlist.strings, and the String Catalog's Chinese text. iOS offers
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
  echo "  $(basename "$dir"): $(cd "$dir" && ls | paste -sd' ' -)"
done
[[ "$found" == true ]] || echo "  (none)"

for language in en zh-Hant; do
  [[ -f "$app/$language.lproj/InfoPlist.strings" ]] \
    || fail "The app has no $language.lproj/InfoPlist.strings: iOS would not offer $language."
done
# The String Catalog compiles to one Localizable.strings per translated
# language; English, its source, may need none.
[[ -f "$app/zh-Hant.lproj/Localizable.strings" ]] \
  || fail "The app has no zh-Hant.lproj/Localizable.strings: the String Catalog's Chinese text is missing."

[[ "$failed" == false ]]
echo "Both languages are in the app."
