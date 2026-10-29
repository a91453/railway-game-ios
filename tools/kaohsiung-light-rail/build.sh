#!/bin/sh
# Swift 6.4 and the common toolchain; pass absolute destination.
set -eu
out="$1"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"
caf="klrt-caf-c1,klrt-caf-s1,klrt-caf-r,klrt-caf-s2,klrt-caf-c2"
cit="klrt-citadis-m1,klrt-citadis-sc1,klrt-citadis-np,klrt-citadis-sc2,klrt-citadis-m2"
for fleet in caf citadis; do
    if [ "$fleet" = caf ]; then ids="$caf"; else ids="$cit"; fi
    far=$(echo "$ids" | sed 's/,/-far,/g;s/$/-far/')
    tools/train-models/run.sh "$out/$fleet" --ids "$ids,$far" --assembly-spec "tools/kaohsiung-light-rail/assembly-$fleet.json"
    node tools/train-models/package.mjs "$out/$fleet"
done
