#!/bin/sh
set -eu
modules=$(find .build/out/Intermediates.noindex -path '*/GamePresentation-t.build/Objects-normal/*/Modules/GamePresentation.swiftmodule' | head -1)
objects=${modules%/Modules/GamePresentation.swiftmodule}
coremodules=$(find .build/out/Intermediates.noindex -path '*/GameCore-t.build/Objects-normal/*/Modules/GameCore.swiftmodule' | head -1)
coreobjects=${coremodules%/Modules/GameCore.swiftmodule}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 6 -warnings-as-errors -I "$objects/Modules" -I "$coreobjects/Modules" tools/new-taipei-lrt/compare-assembly.swift "$objects"/*.o "$objects"/Modules/*.o "$coreobjects"/*.o "$coreobjects"/Modules/*.o -o "$work/compare"
"$work/compare" "$1" "$2"
