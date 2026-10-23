# EstateKit exporter

See [the skill](../../.claude/skills/estate-kit/SKILL.md) for recipes, coordinates, support contracts and rebuild instructions.

`rebuild.sh OUTPUT` runs export, shared GLB encoding tests, Chromium rendering and viewer checks, full PNG decoding, Swift 6.4 warnings-as-errors and the three affected XCTest suites, then creates a verified ZIP. Output must be outside this public checkout. `export.sh` checks every native vertex through the game loader. `verify.mjs` re-encodes all GLBs byte for byte and checks every image SHA and rotated scene footprint. `decode-images.py` independently decodes RGBA and alpha bounds. `browser-check.mjs` exercises search, four categories, every model, seven directions, drag orbit, zoom, backgrounds, downloads and mobile width. `bundle.py` inventories SHA, decompresses and compares every ZIP member.

After finalizing the public producer commit, rerun `python3 tools/estate-kit/bundle.py OUTPUT` so `source.json` records a clean producer. Opening images is still required; automated geometry and alpha checks do not judge visible connections or appearance.
