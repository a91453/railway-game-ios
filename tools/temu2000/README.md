# TEMU2000 static asset rebuild

`Map3DTEMU2000.swift` is the only model recipe. Export five independent units
(TED leading/trailing, TEMA, TEP, TEMB) and a complete eight-car formation.
All final M3DM, GLB and seven-direction PNGs come from that Swift model.
Native coordinates: metres, +X front, +Y left, +Z up, rail Z=0.
`StationKitBuilder` is X/front, Y/up, Z/right and `Model.flat` converts once.

Requires Swift 6.4, Node, Chromium, Playwright, Pillow and Blender for an
independent GLB import audit. Build outside the public repository:

```sh
PATH=/workspace/swift/usr/bin:$PATH tools/temu2000/export.sh OUT
node tools/temu2000/render.mjs OUT
node tools/temu2000/clay.mjs OUT
node tools/temu2000/verify.mjs OUT
python3 tools/temu2000/verify-png.py OUT
node tools/temu2000/browser-check.mjs OUT
blender -b --python tools/temu2000/glb-audit.py -- OUT
```

If geometry changes, preserve the actual preceding export separately and run
`node tools/temu2000/feedback-compare.mjs OUT PRIOR_OUT` after the new export.
It uses matching native cameras and metre bounds. After the public producer
commit is fixed, run `python3 tools/temu2000/bundle.py OUT PUBLIC_COMMIT` for
source/SHA records and the filewise verified ZIP.

See `docs/art/temu2000-2026-10-26/README.md` for sourced dimensions,
proportional estimates and visual review. Complete generated art belongs in
the private repository. The public branch registers static models in
`Map3DModelPack` and does not change the operating Puyuma train mapping.
