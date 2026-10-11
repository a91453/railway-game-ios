#!/bin/bash
# Builds the 3D city view (ARCHITECTURE decision 152) into the app's bundled
# folder RailwayGameApp/Resources/CityView: compiles the Taiwanese areas'
# tiles, builds the vendored jeantimex/tokyo page (Web/CityView) with Vite,
# and writes the notices of everything the page bundles.
#
# Before the first run (see tools/procedural-city/README.md):
#   (cd Web/CityView && npm ci && node tools/assets/fetch_textures.mjs)
#   python3 tools/procedural-city/taiwan_area.py buildings 2026-09-23.1 kaohsiung Web/CityView/data/raw/kaohsiung
#   python3 tools/procedural-city/taiwan_area.py osm taiwan.pbf kaohsiung Web/CityView/data/raw/kaohsiung
#   (and the same two for taichung)
#
# Run from the repository root. VITE_CONFIG may name another Vite config
# with the same settings as Web/CityView/vite.config.js.
set -euo pipefail

root=$(pwd)
web="$root/Web/CityView"
out="$root/RailwayGameApp/Resources/CityView"
test -f "$web/package.json" || { echo "run from the repository root" >&2; exit 1; }

for area in kaohsiung taichung; do
  node --max-old-space-size=4096 "$web/tools/pipeline/compile.mjs" --area="$area" --no-ads
done
node "$root/tools/procedural-city/shrink_textures.mjs" "$web"
(cd "$web" && ./node_modules/.bin/vite build --config "${VITE_CONFIG:-vite.config.js}" --outDir "$out" --emptyOutDir)
node "$root/tools/procedural-city/notices.mjs" "$web" "$root/RailwayGameApp/Resources/Licenses/CityView-NOTICES.md"
du -sh "$out"
