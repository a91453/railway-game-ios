#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?usage: rebuild.sh PRIVATE_REVISION_DIRECTORY}"
[[ "$output" != "$root"* ]] || { echo 'Output must be outside public checkout' >&2; exit 1; }
swift --version | head -1 | grep -q 'Swift version 6.4'
swift build --target GamePresentation -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
work="$(mktemp -d)"
trap 'rm -r "$work"' EXIT
shopt -s nullglob
objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
includes=(-I "$bin/Modules")
if [[ ${#objects[@]} -eq 0 ]]; then
  objects=(); includes=()
  for component in GameCore GamePresentation; do
    for target in "$root"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
      if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
        includes+=(-I "$target/Modules"); objects+=("$target"/*.o "$target"/Modules/*.o); break
      fi
    done
  done
fi
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/depot-yard-kit/export.swift "${objects[@]}" -o "$work/depot-export"
"$work/depot-export" "$output"
node tools/depot-yard-kit/render.mjs "$output"
