#!/bin/sh
# Build the exporter against the package and run it (Linux or macOS, Swift 6.4):
#   tools/train-models/run.sh OUT [export.swift arguments...]
# e.g. tools/train-models/run.sh /tmp/after --tag after
#      tools/train-models/run.sh /tmp/x --lock tools/train-models/hashes.lock.json   (write the lock)
# `@testable import` needs the debug build, so this builds debug.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"
swift build >&2
bin="$(swift build --show-bin-path)"
out="$1"; shift
mkdir -p "$out"
if [ ! -x "$out/.export" ] || [ tools/train-models/export.swift -nt "$out/.export" ]; then
  swiftc -swift-version 6 -I "$bin" tools/train-models/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o "$out/.export"
fi
"$out/.export" "$out" "$@"
