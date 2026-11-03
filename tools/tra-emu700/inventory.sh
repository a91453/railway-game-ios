#!/bin/sh
# Enumerate the real runtime; the shared exporter's --all is not this operation.
# Run from a checkout with Swift 6.4: inventory.sh OUT [CLEAN_CHECKOUT]
set -eu
helper_repo="$(cd "$(dirname "$0")/../.." && pwd)"
inventory_repo="${2:-$helper_repo}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
python3 - "$inventory_repo" "$work" <<'PY'
from pathlib import Path
import sys
repo,work=map(Path,sys.argv[1:])
source=(repo/'tools/train-models/export.swift').read_text()
needle='wanted = pack.models.map(\\.name).filter { $0.hasPrefix("set-") || $0.hasPrefix("style-") }'
if source.count(needle)!=1:raise SystemExit('Shared exporter changed; inspect its real inventory path before adapting.')
source=source.replace(needle,'wanted = (pack.models + studies.models).map(\\.name)')
anchor='let studies = Map3DModelPack.studies'
if source.count(anchor)!=1:raise SystemExit('Missing actual studies runtime inventory')
source=source.replace(anchor,anchor+'''
try FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)
try json(["standard": pack.models.map(\\.name), "studies": studies.models.map(\\.name),
    "standard_vertex_bytes": pack.models.reduce(0) { $0 + $1.vertices.count * MemoryLayout<Map3DVertex>.stride },
    "studies_vertex_bytes": studies.models.reduce(0) { $0 + $1.vertices.count * MemoryLayout<Map3DVertex>.stride }
]).write(to: URL(fileURLWithPath: outputPath).appendingPathComponent("runtime-inventory.json"))
''')
(work/'inventory.swift').write_text(source)
runner=(repo/'tools/train-models/run.sh').read_text()
lines=runner.splitlines()
indices=[i for i,line in enumerate(lines) if line.startswith('repo=')]
if len(indices)!=1:raise SystemExit('Inspect changed shared runner before adapting')
lines[indices[0]]='repo="$EMU700_INVENTORY_REPO"'
runner='\n'.join(lines)+'\n'
runner=runner.replace('tools/train-models/export.swift','"$EMU700_INVENTORY_SOURCE"')
(work/'run.sh').write_text(runner)
PY
EMU700_INVENTORY_REPO="$inventory_repo" EMU700_INVENTORY_SOURCE="$work/inventory.swift" sh "$work/run.sh" "$1"
