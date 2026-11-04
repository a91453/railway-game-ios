#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?private output directory}"
swift --version | head -1 | grep -q 'Swift version 6.4'
python3 tools/cable-support-studies/test_geometry.py
node --test tools/station-kit/package.test.mjs
python3 tools/cable-support-studies/produce.py "$output"
node tools/cable-support-studies/render.mjs "$output"
node tools/cable-support-studies/verify.mjs "$output"
python3 tools/cable-support-studies/decode-images.py "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
tools/cable-support-studies/check-native.sh "$output"
swift test --skip-build --filter 'Map3DStationKitTests|Map3DModelFileTests|Map3DDetailKitTests'
