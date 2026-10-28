#!/bin/sh
# Decision 458: rebuild the 3D map's Kenney scenery (conifers, bush clumps,
# horizontal tank) into RailwayGameApp/Resources/Models/kenney-*.m3dmodel.
# usage (repository root, Node 22, tools/glb-to-m3dmodel's npm ci done):
#   tools/kenney-props/build.sh [WORK_DIR]
set -eu
work="${1:-$(mktemp -d)}"
node tools/kenney-props/reshape.mjs "$work"
for manifest in "$work"/kenney-*.manifest.json; do
  id="$(basename "$manifest" .manifest.json)"
  node tools/glb-to-m3dmodel/bridge.mjs --manifest "$manifest" --output "$work/$id.m3dmodel"
  cp "$work/$id.m3dmodel" "RailwayGameApp/Resources/Models/$id.m3dmodel"
done
ls -l RailwayGameApp/Resources/Models/kenney-*.m3dmodel
