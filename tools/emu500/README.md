# EMU500 native static reconstruction

Swift 6.4 only, warnings as errors. Recipe: `Sources/GamePresentation/Map3DEMU500.swift`.
Four units EMC / EP / ET / EM; EM local cab faces +X and is rotated 180° in formation.
Native metres +X front +Y left +Z up, rail Z=0. Builder X/front Y/up Z/right;
Model.flat converts once. glTF = (native.x, native.z, -native.y).

```sh
PATH=/workspace/swift/usr/bin:$PATH tools/emu500/export.sh OUT
node tools/emu500/render.mjs OUT
node tools/emu500/clay.mjs OUT
node tools/emu500/verify.mjs OUT
python3 tools/emu500/geometry-audit.py OUT
python3 tools/emu500/verify-png.py OUT
blender -b --python tools/emu500/glb-audit.py -- OUT
node tools/emu500/browser-check.mjs OUT
```

Open and compare actual native previews before continuing. On geometry changes keep the
actual preceding model and recipe first, export to a new OUT, then run
`node tools/emu500/feedback-compare.mjs OUT PRIOR_OUT` with matching metre cameras.
Render/clay/browser/GLB tools adapt TEMU2000's export infrastructure only; its
body, doors, wheels and formation are not used by this recipe. TEMU1000 is
exported solely for style comparison. Requires Node/Playwright/Chromium,
Python/Pillow/NumPy and Blender; no external generation service.

After committing all producer code, `python3 tools/emu500/bundle.py OUT COMMIT`
checks committed source bytes and makes SHA records and a ZIP. Run browser-check again
to verify real ZIP download, then unpack with Python zipfile and compare every byte.
Full package belongs in the private repository. User explicitly requests ZIP and
true prior models, overriding the default archive retention guideline this task.

Model registry only. EMU500 has no dedicated operating type binding on this base;
merging this PR does not make it appear as an operating train.

Additional final checks:

```sh
python3 tools/emu500/support-audit.py OUT
node tools/emu500/standalone.mjs OUT
node tools/emu500/offline-check.mjs OUT
```

The offline viewer embeds native/GLB/PNG payloads and opens directly from a local
file. ZIP remains a separate download in the HTTP viewer and private package.
Ray support audit tests actual broad glass faces plus an artificial floating fault;
it is sampled support evidence, not exhaustive intersection certification.
