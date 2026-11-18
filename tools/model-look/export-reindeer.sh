#!/usr/bin/env bash
# tools/model-look: decision 840 reindeer, now and as first integrated, as .m3dmodel files for shoot.mjs.
#   export-reindeer.sh OUTPUT_DIRECTORY
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:?usage: export-reindeer.sh OUTPUT_DIRECTORY}"; shift
swift build >&2
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules"); objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=(-I "$bin"); objects=("$bin/GamePresentation.o" "$bin/GameCore.o")
fi
swiftc -swift-version 6 "${includes[@]}" "tools/model-look/export-reindeer.swift" "${objects[@]}" -o "$tmp/export"
"$tmp/export" "$out"
