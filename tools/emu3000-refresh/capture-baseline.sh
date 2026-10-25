#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
base="${1:?usage: capture-baseline.sh BASE_CHECKOUT OUTPUT}"
output="${2:?usage: capture-baseline.sh BASE_CHECKOUT OUTPUT}"
cd "$base"
test "$(git rev-parse HEAD)" = 85d9aa359dfcd6213f76a6559abebd9155806e97 || { echo 'Actual baseline commit 85d9aa35 required' >&2; exit 1; }
swift --version | head -1 | grep -q 'Swift version 6.4' || { echo 'Swift 6.4 required' >&2; exit 1; }
swift build --target GamePresentation -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
shopt -s nullglob
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules")
  objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=(); objects=()
  for component in GameCore GamePresentation; do
    found=false
    for target in "$PWD"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
      if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
        includes+=(-I "$target/Modules"); objects+=("$target"/*.o "$target"/Modules/*.o); found=true; break
      fi
    done
    "$found" || { echo "Cannot locate native $component module" >&2; exit 1; }
  done
fi
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" "$source_dir/capture.swift" "${objects[@]}" -o "$work/emu3000-refresh-export"
"$work/emu3000-refresh-export" "$output"
