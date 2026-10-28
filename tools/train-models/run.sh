#!/bin/sh
# Build the exporter against the package and run it (Linux or macOS, Swift 6.4):
#   tools/train-models/run.sh OUT [export.swift arguments...]
# e.g. tools/train-models/run.sh /tmp/after --tag after
#      tools/train-models/run.sh /tmp/x --lock tools/train-models/hashes.lock.json   (write the lock)
# `@testable import` needs the debug build, so this builds debug.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"
swift --version | head -1 | grep -q "Swift version 6.4" || exit 1
swift build --target GamePresentation -Xswiftc -warnings-as-errors -j 4 >&2
bin="$(swift build --show-bin-path)"
out="$1"; shift
# Generic formation definitions are consumed after the Swift unit export.
# --assembly taipei610 remains a legacy compatibility path; new vehicles use
# --assembly-spec FILE without adding a vehicle-specific Swift branch.
assembly_spec=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "--assembly-spec" ]; then assembly_spec="$argument"; fi
  previous="$argument"
done
if [ "$previous" = "--assembly-spec" ]; then echo 'missing --assembly-spec file' >&2; exit 2; fi
mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ -d "$bin/GamePresentation.build" ]; then
  swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" tools/train-models/export.swift "$bin"/GamePresentation.build/*.swift.o "$bin"/GameCore.build/*.swift.o -o "$work/export"
else
  set -- "$out" "$@"
  # Swift 6.4's integrated build backend uses Objects-normal modules.
  modules="$(find .build/out/Intermediates.noindex -path '*/GamePresentation-t.build/Objects-normal/*/Modules/GamePresentation.swiftmodule' | head -1)"
  objects="${modules%/Modules/GamePresentation.swiftmodule}"
  coremodules="$(find .build/out/Intermediates.noindex -path '*/GameCore-t.build/Objects-normal/*/Modules/GameCore.swiftmodule' | head -1)"
  coreobjects="${coremodules%/Modules/GameCore.swiftmodule}"
  swiftc -swift-version 6 -warnings-as-errors -I "$objects/Modules" -I "$coreobjects/Modules" tools/train-models/export.swift "$objects"/*.o "$objects"/Modules/*.o "$coreobjects"/*.o "$coreobjects"/Modules/*.o -o "$work/export"
  "$work/export" "$@"
  if [ -n "$assembly_spec" ]; then node tools/train-models/assemble.mjs "$out" "$assembly_spec"; fi
  exit
fi
"$work/export" "$out" "$@"
if [ -n "$assembly_spec" ]; then node tools/train-models/assemble.mjs "$out" "$assembly_spec"; fi
