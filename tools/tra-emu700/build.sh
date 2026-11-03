#!/bin/sh
set -eu
ids=''
for role in emc-cab ep et em; do
 for suffix in '' -far; do ids="${ids}${ids:+,}tra-emu700-${role}${suffix}"; done
done
tools/train-models/run.sh "$1" --ids "$ids" --assembly-spec tools/tra-emu700/assembly.json
python3 - "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])/'manifest.json';d=json.loads(p.read_text())
for m in d['models']:
 if m.get('native_kind')=='assembly':continue
 if m['id'].endswith('-far'):m.update(role='far',near=m['id'][:-4])
 else:m.update(role='near',far=m['id']+'-far')
p.write_text(json.dumps(d,indent=2)+'\n')
PY
node tools/train-models/package.mjs "$1"
node tools/train-models/audit.mjs "$1"
