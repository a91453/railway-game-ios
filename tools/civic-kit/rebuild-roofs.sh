#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="${1:?usage: rebuild-roofs.sh PRIVATE_OUTPUT_DIRECTORY}"
python3 - "$root" "$output" <<'PY'
from pathlib import Path
import sys
root,out=map(lambda p:Path(p).resolve(),sys.argv[1:])
if out==root or root in out.parents:raise SystemExit('Previews must be outside public checkout')
PY
tools/civic-kit/export-roofs.sh "$output"
node tools/civic-kit/render-roofs.mjs "$output"
