#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="${1:?output directory}"
swift --version | head -1 | grep -q 'Swift version 6.4'
swift build --target GamePresentation -Xswiftc -warnings-as-errors -j 4
bin="$(swift build --show-bin-path)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules")
  objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=();objects=()
  for component in GameCore GamePresentation; do
    found=false
    for target in "$PWD"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
      if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
        includes+=(-I "$target/Modules");objects+=("$target"/*.o "$target"/Modules/*.o);found=true;break
      fi
    done
    "$found" || exit 1
  done
fi
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/c371-c381/export.swift "${objects[@]}" -o "$work/export"
"$work/export" "$output" "${2:-}"
node tools/c371-c381/package.mjs "$output"
