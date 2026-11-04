#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?output directory}"
fixtures="${2:?fixture directory (produce from the pinned cabin recipes)}"
swift --version | head -1 | grep -q 'Swift version 6.4'
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Compile the real shader even on a runner whose VM exposes no Metal device.
xcrun --sdk macosx metal -c RailwayGameApp/Views/Map3D/Map3DShaders.metal -o "$work/map.air"
xcrun --sdk macosx metallib "$work/map.air" -o "$work/map.metallib"
swift build --target GamePresentation -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
shopt -s nullglob
objects=(); includes=()
if [[ -d "$bin/GamePresentation.build" ]]; then
 includes=(-I "$bin/Modules");objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
 for component in GameCore GamePresentation; do
  found=false
  for target in "$root"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
   if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
    includes+=(-I "$target/Modules");objects+=("$target"/*.o "$target"/Modules/*.o);found=true;break
   fi
  done
  "$found" || { echo "Missing $component build" >&2; exit 1; }
 done
fi
python3 - "$root" "$work/main.swift" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]);text=(root/'RailwayGameApp/Views/Map3D/Map3DMetalView.swift').read_text();block=text.split('// BEGIN NATIVE GLASS PIPELINE')[1].split('// END NATIVE GLASS PIPELINE')[0];block=block[block.index('\n'):]
Path(sys.argv[2]).write_text('import Foundation\nimport Metal\nimport ImageIO\nimport CoreGraphics\nimport UniformTypeIdentifiers\n@testable import GamePresentation\n'+block+'\n'+(root/'tools/native-glass/verify-metal.swift.txt').read_text())
PY
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" "$work/main.swift" "${objects[@]}" -o "$work/verify"
"$work/verify" "$work/map.metallib" "$output" "$fixtures"
