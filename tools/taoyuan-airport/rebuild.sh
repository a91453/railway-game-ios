#!/bin/sh
set -eu
ids=''
for role in dmc1 mc1 mc2 dmc2 dme1 me1 me3 me4 dmb; do
 for suffix in '' -far; do
  ids="${ids}${ids:+,}taoyuan-airport-${role}${suffix}"
 done
done
tools/train-models/run.sh "$1" --ids "$ids" --assembly-spec tools/taoyuan-airport/assembly.json
# Studies have no operating set, so the generic exporter cannot infer their LOD pairs.
python3 - "$1" <<'PYLOD'
import json,sys
from pathlib import Path
path=Path(sys.argv[1])/'manifest.json'
manifest=json.loads(path.read_text())
ids={m['id'] for m in manifest['models']}
for model in manifest['models']:
    if not model['id'].startswith('taoyuan-airport-'):raise ValueError('unexpected model')
    if model['id'].endswith('-far'):
        model['role']='far'
        model['near']=model['id'][:-4]
    else:
        model['role']='near'
        model['far']=model['id']+'-far'
        if model['far'] not in ids:raise ValueError('missing far unit')
path.write_text(json.dumps(manifest,indent=2)+'\n')
PYLOD
node tools/train-models/package.mjs "$1"
node tools/train-models/audit.mjs "$1"
python3 tools/taoyuan-airport/audit.py "$1"
tools/taoyuan-airport/compare-assembly.sh "$1"
blender -b --python tools/taichung-green/import-glb.py -- "$1"
