#!/usr/bin/env bash
# tools/model-look: two exports of the chosen Christmas livery side by side
# (WREATH-NOSE, decision 806's amendment), for shoot-livery.mjs: the plain
# train, the livery as BEFORE draws it, the livery as AFTER draws it.
#   pair-livery.sh BEFORE AFTER OUTPUT_DIRECTORY [BEFORE_LABEL AFTER_LABEL]
# BEFORE and AFTER are `export-winter.sh options` folders (the first from the
# commit before the change). Only their plain and mix files are taken.
set -euo pipefail
before="${1:?usage: pair-livery.sh BEFORE AFTER OUTPUT_DIRECTORY [BEFORE_LABEL AFTER_LABEL]}"
after="${2:?usage: pair-livery.sh BEFORE AFTER OUTPUT_DIRECTORY [BEFORE_LABEL AFTER_LABEL]}"
out="${3:?usage: pair-livery.sh BEFORE AFTER OUTPUT_DIRECTORY [BEFORE_LABEL AFTER_LABEL]}"
mkdir -p "$out"
cp "$before"/*-plain-*.m3dmodel "$before"/*-mix-*.m3dmodel "$out"/
for file in "$after"/*-mix-*.m3dmodel; do
  name="$(basename "$file")"
  cp "$file" "$out/${name/-mix-/-after-}"
done
python3 -I - "$after/options.json" "$out/options.json" "${4:-聖誕（改前）}" "${5:-聖誕（改後）}" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
manifest["variants"] = ["plain", "mix", "after"]
manifest["labels"] = {"mix": sys.argv[3], "after": sys.argv[4]}
json.dump(manifest, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
PY
echo "Wrote $out"
