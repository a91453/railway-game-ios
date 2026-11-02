#!/bin/sh
set -eu
ids=''
for role in dmc1 mc1 mc2 dmc2 dme1 me1 me3 me4 dmb; do
 for suffix in '' -far; do
  ids="${ids}${ids:+,}taoyuan-airport-${role}${suffix}"
 done
done
tools/train-models/run.sh "$1" --ids "$ids" --assembly-spec tools/taoyuan-airport/assembly.json
node tools/train-models/package.mjs "$1"
node tools/train-models/audit.mjs "$1"
python3 tools/taoyuan-airport/audit.py "$1"
tools/taoyuan-airport/compare-assembly.sh "$1"
blender -b --python tools/taichung-green/import-glb.py -- "$1"
