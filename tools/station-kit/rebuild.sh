#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?usage: rebuild.sh PRIVATE_OUTPUT_DIRECTORY}"
python3 - "$root" "$output" <<'PY'
import sys
from pathlib import Path
root,output=map(lambda x:Path(x).resolve(),sys.argv[1:])
if output==root or root in output.parents:
    raise SystemExit('Choose a directory outside the public game checkout; large previews belong in the private repository.')
PY
python3 tools/station-kit/catalog.py --check
node --test tools/station-kit/package.test.mjs
tools/station-kit/export.sh "$output"
node tools/station-kit/render.mjs "$output"
node tools/station-kit/verify.mjs "$output"
node tools/station-kit/browser-check.mjs "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DStationKitTests|Map3DModelFileTests'
