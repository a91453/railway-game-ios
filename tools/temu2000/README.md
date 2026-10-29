# TEMU2000 static asset rebuild

## 2026-10-29 studies revision-2

Producer `2cb46a3660bb500549e81098c66421e8163ee479` corrects the
user-rejected revision-1 lamp layout and side paint. Revision-1 producer
`02d61687481ebdd832edc5c11685af51eca05362` is the actual prior
export used for fixed-camera comparison. See the review record for limits.

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

`Map3DTEMU2000.swift` is the model recipe. Native coordinates are metres,
+X front, +Y left, +Z up, rail Z=0; `StationKitBuilder` converts from its
+Y-up coordinates once. Requires Swift 6.4, Node, Chromium, Playwright,
Pillow and Blender. Build outside the public repository. `render.mjs` creates
the seven-direction PNGs, `glb-audit.py` independently imports each GLB,
and `browser-check.mjs` verifies the delivered viewer and download bytes.
Use `feedback-compare.mjs OUT PRIOR_OUT` with the actual prior export for
matching native cameras and metre scale. The private delivery uses
`tools/train-models/deliver.py` and contains no ZIP.
