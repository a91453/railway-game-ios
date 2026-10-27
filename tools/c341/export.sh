#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="${1:?usage: export.sh OUTPUT_DIRECTORY}"
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
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/c341/export.swift "${objects[@]}" -o "$work/c341-export"
"$work/c341-export" "$output"
node tools/c341/package.mjs "$output"
python3 - "$output" <<'PY'
import hashlib,sys,json
from pathlib import Path
p=Path(sys.argv[1])/'existing-payload.bin'
(p.parent/'existing-payload.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'\n')
b=p.read_bytes();rows=json.loads((p.parent/'existing-segments.json').read_text())
for r in rows:r['sha256']=hashlib.sha256(b[r['offset']:r['offset']+r['length']]).hexdigest()
(p.parent/'existing-segments.json').write_text(json.dumps(rows,indent=2)+'\n')
# The initial checkout predates the EMU800 merge. Compare all its actual bytes too.
legacy=b''.join(b[r['offset']:r['offset']+r['length']] for r in rows if not r['name'].startswith('emu800-'))
(p.parent/'existing-pre-emu800.sha256').write_text(hashlib.sha256(legacy).hexdigest()+'\n')
p.unlink()
PY
