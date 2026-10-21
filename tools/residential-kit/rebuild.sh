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
tools/residential-kit/export.sh "$output"
node tools/residential-kit/render.mjs "$output"
node tools/residential-kit/verify.mjs "$output"
node tools/residential-kit/browser-check.mjs "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
test_log="$(mktemp)"
trap 'rm -f "$test_log"' EXIT
swift test --skip-build --filter 'Map3DResidentialKitTests|Map3DStationKitTests|Map3DModelFileTests' 2>&1 | tee "$test_log"
# Swift Build can finish the last (empty) runner successfully after another
# runner reports XCTest failures. Require the actual intended suites to pass.
python3 - "$test_log" <<'PYTEST'
import re,sys
text=open(sys.argv[1]).read()
if re.search(r"Test (?:Suite|Case) .* failed",text):raise SystemExit('XCTest reported a failure')
for name in ['Map3DResidentialKitTests','Map3DStationKitTests','Map3DModelFileTests']:
    if not re.search(r"Test Suite '"+name+r"' passed",text):raise SystemExit('Missing passing suite: '+name)
print('VERIFIED all three intended XCTest suites passed (not only the runner exit code).')
PYTEST
python3 tools/residential-kit/bundle.py "$output"
