#!/bin/bash
# Reuse the shared export implementation with a study-only lookup adapter.
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
out=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
python3 - "$work/export.swift" <<'PY'
import sys
s=open('tools/train-models/export.swift').read()
anchor='    if let at = pack.index(of: name)'
s=s.replace(anchor,'''    for unit in Map3DKaohsiung.Unit.allCases {
        for far in [false, true] {
            let m = Map3DKaohsiung.model(unit, far: far, shellOnly: true)
            if m.name == name { return (m, nil) }
        }
    }
'''+anchor,1)
open(sys.argv[1],'w').write(s)
PY
objects=$(find .build/out/Intermediates.noindex -path '*/GamePresentation-t.build/Objects-normal/*/Modules/GamePresentation.swiftmodule' | head -1)
objects=${objects%/Modules/GamePresentation.swiftmodule}
core=$(find .build/out/Intermediates.noindex -path '*/GameCore-t.build/Objects-normal/*/Modules/GameCore.swiftmodule' | head -1)
core=${core%/Modules/GameCore.swiftmodule}
swiftc -swift-version 6 -warnings-as-errors -I "$objects/Modules" -I "$core/Modules" "$work/export.swift" "$objects"/*.o "$objects"/Modules/*.o "$core"/*.o "$core"/Modules/*.o -o "$work/export"
"$work/export" "$out" --ids kaohsiung-dm1-shell,kaohsiung-t-shell,kaohsiung-dm2-shell,kaohsiung-dm1-far-shell,kaohsiung-t-far-shell,kaohsiung-dm2-far-shell
