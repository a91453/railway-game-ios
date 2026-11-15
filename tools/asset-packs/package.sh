#!/bin/bash
# Decision 776: packs each city's map pack into an Apple-hosted asset pack
# (`<assetPackID>.aar`) with Xcode's `ba-package`. macOS with Xcode 26 or
# later only. Usage: tools/asset-packs/package.sh <output folder>
#
# Each manifest in RailwayGameApp/AssetPacks/ names its files relative to
# RailwayGameApp/Resources, so the pack holds `MapPacks/<folder>/...`, the
# path the app asks for (OverseasMap.assetPackManifestPath).
set -euo pipefail
out="${1:?usage: package.sh <output folder>}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
cd "$repo/RailwayGameApp/Resources"
for manifest in "$repo"/RailwayGameApp/AssetPacks/*.json; do
  id="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["assetPackID"])' "$manifest")"
  xcrun ba-package "$manifest" -o "$out/$id.aar"
  echo "$out/$id.aar"
done
