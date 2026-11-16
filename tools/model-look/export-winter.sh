#!/usr/bin/env bash
# tools/model-look: the winter event's looks as .m3dmodel files for shoot.mjs.
#   export-winter.sh lights OUTPUT_DIRECTORY [before]
#     every kind of station building and the kit's exits with the lights hung on them
#   export-winter.sh livery OUTPUT_DIRECTORY [MODEL_NAME...]
#     prints each running car's painted side by part; writes the named cars plain and in the Christmas livery
set -euo pipefail
cd "$(dirname "$0")/../.."
kind="${1:?usage: export-winter.sh lights|livery OUTPUT_DIRECTORY ...}"; out="${2:?usage: export-winter.sh lights|livery OUTPUT_DIRECTORY ...}"; shift 2
swift build >&2
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules"); objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=(-I "$bin"); objects=("$bin/GamePresentation.o" "$bin/GameCore.o")
fi
swiftc -swift-version 6 "${includes[@]}" "tools/model-look/export-winter-$kind.swift" "${objects[@]}" -o "$tmp/export"
"$tmp/export" "$out" "$@"
