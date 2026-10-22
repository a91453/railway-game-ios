#!/bin/bash
# Decision 352: redraws RailwayGameApp/Resources/Map3D/Map3DSigns.png.
#
#   tools/map3d-signs/build.sh <Noto Sans TC folder>
#
# (see render.cjs for the font), then keeps it to 256 colours (Pillow,
# MIT-CMU), a quarter of the size, with no visible change to the neon.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
NODE_PATH="${NODE_PATH:-$(npm root -g)}" node "$here/render.cjs" "$1" "$work/atlas.png"
python3 -I -c "
import sys
from PIL import Image
Image.open(sys.argv[1]).convert('RGB').quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(sys.argv[2], optimize=True)
" "$work/atlas.png" "$repo/RailwayGameApp/Resources/Map3D/Map3DSigns.png"
