#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?usage: export.sh OUTPUT_DIRECTORY}"
swift --version | head -1 | grep -q 'Swift version 6.4' || { echo 'Swift 6.4 is required' >&2; exit 1; }
swift build --target GamePresentation -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
shopt -s nullglob
objects=()
includes=()
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules")
  objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  # Swift 6.4 defaults to Swift Build; older native SwiftPM uses the layout above.
  for component in GameCore GamePresentation; do
    found=false
    for target in "$root"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
      if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
        includes+=(-I "$target/Modules")
        objects+=("$target"/*.o "$target"/Modules/*.o)
        found=true
        break
      fi
    done
    "$found" || { echo "Cannot locate native $component module" >&2; exit 1; }
  done
fi
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/estate-kit/export.swift "${objects[@]}" -o "$work/scene-kit-export"
"$work/scene-kit-export" "$output"
node tools/station-kit/package.mjs "$output"
