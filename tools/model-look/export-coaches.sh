#!/usr/bin/env bash
# tools/model-look: decision 708 coach stop and coaches as .m3dmodel files, from this checkout's
# recipes.  export-coaches.sh OUTPUT_DIRECTORY 
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${1:?usage: export-coaches.sh OUTPUT_DIRECTORY }"
swift build >&2
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# SwiftPM's two layouts: per-file objects (Linux), one object a module (Xcode's build system).
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules"); objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=(-I "$bin"); objects=("$bin/GamePresentation.o" "$bin/GameCore.o")
fi
swiftc -swift-version 6 "${includes[@]}" tools/model-look/export-coaches.swift "${objects[@]}" -o "$tmp/export"
"$tmp/export" "$out"
