#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="$root/docs/art/generated-2026-10-21-scene-kit/native3d"
node --test tools/scene-kit/package.test.mjs
tools/scene-kit/export.sh "$output"
node tools/scene-kit/render.mjs "$output"
node tools/scene-kit/review.mjs "$output"
node tools/scene-kit/verify.mjs "$output"
node tools/scene-kit/browser-check.mjs "$output"
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DSceneKitTests|Map3DModelFileTests'
