#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?private output directory}"
swift --version | head -1 | grep -q 'Swift version 6.4'
python3 tools/ferry-berthing-studies/test_geometry.py
node --test tools/station-kit/package.test.mjs
python3 tools/ferry-berthing-studies/produce.py "$output"
node tools/ferry-berthing-studies/render.mjs "$output"
python3 tools/ferry-berthing-studies/pose-fixtures.py "$output"
node tools/ferry-berthing-studies/verify.mjs "$output"
python3 tools/ferry-berthing-studies/decode-images.py "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
tools/ferry-berthing-studies/check-native.sh "$output"
swift test --skip-build --filter 'Map3DCoastalKitTests|Map3DStationKitTests|Map3DModelFileTests|Map3DDetailKitTests'
