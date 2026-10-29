# TEMU2000 static asset rebuild

## 2026-10-29 studies revision

The current delivery uses `Map3DTEMU2000.studyModel` and the shared
`tools/train-models` exporter. The operating `Map3DTEMU2000.model` remains
the earlier payload. The five near and five far units are registered only in
`Map3DModelPack.studies`; their complete eight-car formations are generic
M3DAssembly scenes from [`assembly-spec.json`](assembly-spec.json). The near
scene exceeds the 15,000-triangle *single M3DM* limit, so it is never used as
one native unit file. See [the research and review record](../../docs/art/temu2000-2026-10-29/README.md).

```sh
PATH=/workspace/swift/usr/bin:$PATH tools/train-models/run.sh OUT --tag final \
  --ids temu2000-leading,temu2000-tema,temu2000-tep,temu2000-temb,temu2000-trailing,temu2000-leading-far,temu2000-tema-far,temu2000-tep-far,temu2000-temb-far,temu2000-trailing-far \
  --assembly-spec tools/temu2000/assembly-spec.json
node tools/train-models/package.mjs OUT
node tools/train-models/audit.mjs OUT
node tools/temu2000/study-audit.mjs OUT
node tools/train-models/check.mjs OUT
```

The earlier exporter and bundle scripts below document the prior delivered
version. They are not the 2026-10-29 delivery command.

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
