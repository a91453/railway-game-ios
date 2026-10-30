#!/bin/sh
set -eu
out="$1"
for fleet in haifeng shanlan; do
 ids="$fleet-emu500-emc,$fleet-emu500-ep,$fleet-emu500-et,$fleet-emu500-em"
 far=$(echo "$ids" | sed 's/,/-far,/g;s/$/-far/')
 tools/train-models/run.sh "$out/$fleet" --ids "$ids,$far" --assembly-spec "tools/tourism-emu500/assembly-$fleet.json"
 node tools/train-models/package.mjs "$out/$fleet"
done
