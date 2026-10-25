# TEMU1000 static asset rebuild

Native coordinates: metres, +X front, +Y left, +Z up, rail Z=0. `StationKitBuilder` is X/front, Y/up, Z/right and `Model.flat` converts once. Export independent leading, trailing, middle and pantograph units plus an eight-car formation. Placement order and centres are in `manifest.json`; all units are pre-oriented, so no extra rotation.

Requires Swift 6.4, Node, Chromium, Playwright and Pillow. Build outside the public repository:

```sh
PATH=/workspace/swift/usr/bin:$PATH tools/temu1000/export.sh OUT
node tools/temu1000/render.mjs OUT
node tools/temu1000/clay.mjs OUT
python3 tools/temu1000/verify-png.py OUT
node tools/temu1000/browser-check.mjs OUT
python3 tools/temu1000/bundle.py OUT PUBLIC_PRODUCER_COMMIT
```

See `docs/art/temu1000-2026-10-25/README.md` for sources, proportions and visual review. Full native, GLB, views, viewer and ZIP live in the private repository. The public `taroko` set maps to these units after the stacked public PR is merged.
