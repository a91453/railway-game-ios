#!/usr/bin/env bash
set -euo pipefail
out=${1:?output directory}
ids=tra-r100-r122-orange-locomotive,tra-r100-r122-orange-locomotive-far,tra-r100-r123-breezy-blue-locomotive,tra-r100-r123-breezy-blue-locomotive-far,tra-breezy-blue-coach-mixed,tra-breezy-blue-coach-mixed-far,tra-breezy-blue-coach-exhibition,tra-breezy-blue-coach-exhibition-far,tra-breezy-blue-coach-long-seat,tra-breezy-blue-coach-long-seat-far,tra-breezy-blue-coach-rotating-seat,tra-breezy-blue-coach-rotating-seat-far
tools/train-models/run.sh "$out" --ids "$ids" --assembly-spec tools/tra-r100/formation.json
python3 - "$out" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])/'manifest.json';m=json.loads(p.read_text())
ids={r['id'] for r in m['models']}
for r in m['models']:
    if r.get('native_kind')=='assembly':continue
    r['role']='far' if r['id'].endswith('-far') else 'near'
    r['category']='coach' if '-coach-' in r['id'] else 'locomotive'
    if r['id']+'-far' in ids:r['far']=r['id']+'-far'
p.write_text(json.dumps(m,indent=2)+'\n')
PY
node tools/train-models/package.mjs "$out"
node tools/train-models/audit.mjs "$out"
node tools/tra-r100/verify.mjs "$out"
swift -swift-version 6 -warnings-as-errors tools/tra-r100/assembly-check.swift "$out" tools/tra-r100/formation.json
