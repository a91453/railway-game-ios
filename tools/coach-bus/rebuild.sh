#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?usage: rebuild.sh PRIVATE_OUTPUT_DIRECTORY}"
python3 - "$root" "$output" <<'PY'
import sys
from pathlib import Path
root,output=map(lambda x:Path(x).resolve(),sys.argv[1:])
if output==root or root in output.parents:raise SystemExit('Output must be outside the public checkout; large art belongs in the private repository.')
PY
node --test tools/station-kit/package.test.mjs
tools/coach-bus/export.sh "$output"
node tools/coach-bus/render.mjs "$output"
node tools/coach-bus/verify.mjs "$output"
node tools/coach-bus/browser-check.mjs "$output"
python3 tools/coach-bus/verify-png.py "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
test_log="$(mktemp)"
trap 'rm -f "$test_log"' EXIT
swift test --skip-build --filter 'Map3DCoachBusTests|Map3DLowFloorBusTests|Map3DShuttleBusTests|Map3DCityBusTests|Map3DStreetLifeTests|Map3DModelTests|Map3DModelFileTests' 2>&1 | tee "$test_log"
# Swift Build can finish the last (empty) runner successfully after another
# runner reports XCTest failures. Require the actual intended suites to pass.
python3 - "$test_log" <<'PYTEST'
import re,sys
text=open(sys.argv[1]).read()
if re.search(r"Test (?:Suite|Case) .* failed",text):raise SystemExit('XCTest reported a failure')
for name in ['Map3DCoachBusTests','Map3DLowFloorBusTests','Map3DShuttleBusTests','Map3DCityBusTests','Map3DStreetLifeTests','Map3DModelTests','Map3DModelFileTests']:
    if not re.search(r"Test Suite '"+name+r"' passed",text):raise SystemExit('Missing passing suite: '+name)
print('VERIFIED all seven intended XCTest suites passed (not only the runner exit code).')
PYTEST

# Optional decision 593 livery studies; the ordinary street model export above
# remains byte-identical and the studies stay outside the public checkout.
if [[ $# -ge 2 ]]; then
  livery_output="$2"
  python3 - "$root" "$livery_output" <<'PYCHECK'
import sys
from pathlib import Path
root,output=map(lambda x:Path(x).resolve(),sys.argv[1:])
if output==root or root in output.parents:raise SystemExit('Livery output must be private')
PYCHECK
  bin="$(swift build --show-bin-path)"
  work="$(mktemp -d)"
  trap 'rm -rf "$test_log" "$work"' EXIT
  shopt -s nullglob
  objects=(); includes=()
  if [[ -d "$bin/GamePresentation.build" ]]; then
    includes=(-I "$bin/Modules")
    objects=("$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o)
  else
    for component in GameCore GamePresentation; do
      for target in "$root"/.build/out/Intermediates.noindex/RailwayGame.build/Debug-*/"$component"-t.build/Objects-normal/*; do
        if [[ -f "$target/Modules/$component.swiftmodule" ]]; then
          includes+=(-I "$target/Modules")
          objects+=("$target"/*.o "$target"/Modules/*.o)
          break
        fi
      done
    done
  fi
  swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/coach-bus/liveries-export.swift "${objects[@]}" -o "$work/liveries-export"
  "$work/liveries-export" "$livery_output"
  node tools/coach-bus/liveries-render.mjs "$livery_output"
  python3 tools/coach-bus/liveries-verify.py "$livery_output"
fi
