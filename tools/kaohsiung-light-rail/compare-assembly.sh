#!/bin/sh
set -eu
legacy=$(find .build -path "*/debug/Modules/GamePresentation.swiftmodule" -print -quit)
bin=${legacy%/Modules/GamePresentation.swiftmodule}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "$legacy" ] && [ -d "$bin/GamePresentation.build" ]; then
    swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" tools/kaohsiung-light-rail/compare-assembly.swift "$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o -o "$work/compare"
else
    modules=$(find .build/out/Intermediates.noindex -path '*/GamePresentation-t.build/Objects-normal/*/Modules/GamePresentation.swiftmodule' | head -1)
    objects=${modules%/Modules/GamePresentation.swiftmodule}
    coremodules=$(find .build/out/Intermediates.noindex -path '*/GameCore-t.build/Objects-normal/*/Modules/GameCore.swiftmodule' | head -1)
    coreobjects=${coremodules%/Modules/GameCore.swiftmodule}
    swiftc -swift-version 6 -warnings-as-errors -I "$objects/Modules" -I "$coreobjects/Modules" tools/kaohsiung-light-rail/compare-assembly.swift "$objects"/*.o "$objects"/Modules/*.o "$coreobjects"/*.o "$coreobjects"/Modules/*.o -o "$work/compare"
fi
"$work/compare" "$1"
