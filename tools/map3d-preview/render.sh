#!/bin/bash
# The 3D map's preview pictures (decision 238): renders a dumped scene in
# headless Chromium, through the WebGL page beside this script, which
# draws as Map3DShaders.metal does.
#
#   tools/map3d-preview/render.sh <dump prefix> <out prefix> <view>[,<view>...]
#
# <dump prefix> is what Map3DPreviewDump wrote (MAP3D_DUMP); each view is
# one named in its MAP3D_VIEWS. Writes <out prefix>-<view>-textured.png
# and <out prefix>-<view>-shadows.png.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for part in vertices indices svertices sindices json; do ln -s "$(realpath "$1.$part")" "$work/demo.$part"; done
cp "$here/index.html" "$work/"
cp "$repo/RailwayGameApp/Resources/Map3D/Map3DSurfaces.png" "$work/"
out=$(realpath -m "$2")
cd "$here" && node render.cjs "$work" "$out" "$3"
