#!/usr/bin/env bash
# parity.sh PYTHON_PACK: builds the package, exports the Swift recipes and
# compares them with the pack produce.py wrote there.
set -euo pipefail
cd "$(dirname "$0")/../.."
pack="${1:?usage: parity.sh PYTHON_PACK}"
swift build >&2
bin="$(swift build --show-bin-path)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -d "$bin/GamePresentation.build" ]]; then
  includes=(-I "$bin/Modules"); objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
else
  includes=(-I "$bin"); objects=("$bin/GamePresentation.o" "$bin/GameCore.o")
fi
swiftc -swift-version 6 "${includes[@]}" tools/airport-aircraft-studies/export.swift "${objects[@]}" -o "$tmp/export"
"$tmp/export" "$tmp/models" >/dev/null
python3 tools/airport-aircraft-studies/parity.py "$pack" "$tmp/models"
