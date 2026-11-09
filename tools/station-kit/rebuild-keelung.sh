#!/usr/bin/env bash
# Rebuild decision 665's Keelung-only revision from the public Swift recipe.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:?usage: rebuild-keelung.sh PRIVATE_REVISION_DIRECTORY}"
mkdir -p "$out"
swift build
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
objects=(); includes=()
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules")
  objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  for component in GameCore GamePresentation; do
    for target in .build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
      if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
        includes+=(-I "$target/Modules")
        objects+=("$target"/*.o "$target"/Modules/*.o)
        break
      fi
    done
  done
fi
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" \
  tools/station-kit/export-keelung.swift "${objects[@]}" -o "$tmp/export"
"$tmp/export" "$out"
node tools/station-kit/package.mjs "$out"
python3 tools/station-kit/make-keelung-viewer.py "$out"
node tools/station-kit/render-keelung.mjs "$out"
