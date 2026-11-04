#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
swift_version="$(swift --version 2>&1)"
printf '%s\n' "$swift_version"
[[ "$swift_version" =~ Swift\ version\ 6\.4([.[:space:]]|$) ]] || { echo 'Swift 6.4 required' >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bin="$(swift build --show-bin-path)"
shopt -s nullglob
objects=(); includes=()
if [[ -d "$bin/GamePresentation.build" ]]; then
 includes=(-I "$bin/Modules"); objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
 for component in GameCore GamePresentation; do
  for target in "$root"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
   if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
    includes+=(-I "$target/Modules");objects+=("$target"/*.o "$target"/Modules/*.o);break
   fi
  done
 done
fi
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/native-glass/check-cabins.swift "${objects[@]}" -o "$work/check"
"$work/check" "${1:?fixtures}" "${2:?report JSON}"
