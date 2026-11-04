#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?output directory}"
fixtures="${2:?fixture directory (produce from the pinned cabin recipes)}"
swift_version="$(swift --version 2>&1)"
printf '%s\n' "$swift_version"
[[ "$swift_version" =~ Swift\ version\ 6\.4([.[:space:]]|$) ]] || { echo 'Swift 6.4 required' >&2; exit 1; }
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Compile the real shader even on a runner whose VM exposes no Metal device.
xcrun --sdk macosx metal -c RailwayGameApp/Views/Map3D/Map3DShaders.metal -o "$work/map.air"
xcrun --sdk macosx metallib "$work/map.air" -o "$work/map.metallib"
swift build --target GamePresentation -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
shopt -s nullglob
source "$root/tools/native-glass/build-inputs.sh"
native_glass_build_inputs "$root" "$bin"
python3 - "$root" "$work/main.swift" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]);text=(root/'RailwayGameApp/Views/Map3D/Map3DMetalView.swift').read_text();block=text.split('// BEGIN NATIVE GLASS PIPELINE')[1].split('// END NATIVE GLASS PIPELINE')[0];block=block[block.index('\n'):]
Path(sys.argv[2]).write_text('import Foundation\nimport Metal\nimport ImageIO\nimport CoreGraphics\nimport UniformTypeIdentifiers\n@testable import GamePresentation\n'+block+'\n'+(root/'tools/native-glass/verify-metal.swift.txt').read_text())
PY
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" "$work/main.swift" "${objects[@]}" -o "$work/verify"
"$work/verify" "$work/map.metallib" "$output" "$fixtures"
