#!/bin/sh
set -eu
node tools/train-models/render.mjs "$1" --time both
node tools/train-models/render.mjs "$1" --material clay
node tools/train-models/render.mjs "$1" --material silhouette
node tools/taoyuan-airport/common-scale.mjs "$1"
python3 tools/taoyuan-airport/sheets.py "$1"
