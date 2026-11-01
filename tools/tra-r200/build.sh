#!/usr/bin/env bash
set -euo pipefail
out=${1:?output directory}
tools/train-models/run.sh "$out" --ids tra-r200-r216-locomotive,tra-r200-r216-locomotive-far
node tools/train-models/package.mjs "$out"
python3 - "$out" <<'PY2'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])/'manifest.json';m=json.loads(p.read_text())
m['models'][0]['far']=m['models'][1]['id'];m['models'][1]['role']='far'
for r in m['models']:r['category']='locomotive'
p.write_text(json.dumps(m,indent=2)+'\n')
PY2
node tools/train-models/audit.mjs "$out"
node tools/tra-r200/verify.mjs "$out"
