#!/bin/sh
set -eu
out="$1"
for fleet in ankeng danhai; do
    ids="$fleet-lrt-m1,$fleet-lrt-m2,$fleet-lrt-m3,$fleet-lrt-m4,$fleet-lrt-m5"
    far=$(echo "$ids" | sed 's/,/-far,/g;s/$/-far/')
    tools/train-models/run.sh "$out/$fleet" --ids "$ids,$far" --assembly-spec "tools/new-taipei-lrt/assembly-$fleet.json"
    node tools/train-models/package.mjs "$out/$fleet"
done
