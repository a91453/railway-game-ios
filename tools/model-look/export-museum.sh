#!/usr/bin/env bash
# tools/model-look: the railway museum (decision 696) as .m3dmodel files, from this checkout's
# recipes.  export-museum.sh OUTPUT_DIRECTORY EXHIBITS...
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:?usage: export-museum.sh OUTPUT_DIRECTORY EXHIBITS...}"; shift
swift build >&2
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# SwiftPM's two layouts: per-file objects (Linux), one object a module (Xcode's build system).
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules"); objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=(-I "$bin"); objects=("$bin/GamePresentation.o" "$bin/GameCore.o")
fi
swiftc -swift-version 6 "${includes[@]}" tools/model-look/export-museum.swift "${objects[@]}" -o "$tmp/export"
"$tmp/export" "$out" "$@"
