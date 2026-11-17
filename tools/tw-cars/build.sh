#!/bin/sh
# Decision 838: rebuild Taiwan's street cars (saloon, SUV, van, yellow taxi)
# into RailwayGameApp/Resources/Models/tw-*.m3dmodel.
# usage (repository root, Node 22, tools/glb-to-m3dmodel's npm ci done, the
# reference repository checked out beside this one):
#   tools/tw-cars/build.sh [WORK_DIR]
set -eu
kit="${KIT:-../railway-reference-private/Railway/town-scene-reference-clean/source/assets/car-kit/Models/GLB_20format}"
work="${1:-$(mktemp -d)}"
node tools/tw-cars/reshape.mjs "$kit" "$work"
for manifest in "$work"/tw-*.manifest.json; do
  id="$(basename "$manifest" .manifest.json)"
  node tools/glb-to-m3dmodel/bridge.mjs --manifest "$manifest" --output "$work/$id.m3dmodel"
  cp "$work/$id.m3dmodel" "RailwayGameApp/Resources/Models/$id.m3dmodel"
done
ls -l RailwayGameApp/Resources/Models/tw-*.m3dmodel
