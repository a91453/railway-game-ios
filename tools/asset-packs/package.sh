#!/bin/bash
# Decision 776: packs each city's map pack into an Apple-hosted asset pack
# (`<assetPackID>.aar`) with Xcode's `ba-package`. macOS with Xcode 26 or
# later only. Usage: tools/asset-packs/package.sh <output folder> [assetPackID ...]
# With IDs, only those packs (decision 858: a release uploads only the packs
# that changed); an ID no manifest has is an error.
#
# Each manifest in RailwayGameApp/AssetPacks/ names its files relative to
# RailwayGameApp/Resources, so the pack holds `MapPacks/<folder>/...`, the
# path the app asks for (OverseasMap.assetPackManifestPath).
set -euo pipefail
out="${1:?usage: package.sh <output folder> [assetPackID ...]}"
shift
wanted=" $* "
packed=0
repo="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
cd "$repo/RailwayGameApp/Resources"
for manifest in "$repo"/RailwayGameApp/AssetPacks/*.json; do
  id="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["assetPackID"])' "$manifest")"
  if [[ "$wanted" != "  " && "$wanted" != *" $id "* ]]; then continue; fi
  xcrun ba-package "$manifest" -o "$out/$id.aar"
  echo "$out/$id.aar"
  packed=$((packed + 1))
done
if [[ "$wanted" != "  " && "$packed" -ne "$#" ]]; then
  echo "package.sh: asked for $# pack(s) ($*), found $packed." >&2
  exit 1
fi
