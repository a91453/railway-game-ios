#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?private output directory}"
swift --version | head -1 | grep -q 'Swift version 6.4'
python3 tools/ferry-studies/test_geometry.py
node --test tools/station-kit/package.test.mjs
for group in tamsui cijin dock; do python3 tools/ferry-studies/produce.py "$output" "$group"; done
node tools/ferry-studies/render.mjs "$output"
node tools/ferry-studies/verify.mjs "$output"
python3 tools/ferry-studies/decode-images.py "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
tools/ferry-studies/check-native.sh "$output"
swift test --skip-build --filter 'Map3DCoastalKitTests|Map3DStationKitTests|Map3DModelFileTests'
