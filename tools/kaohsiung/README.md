# Kaohsiung Siemens studies

Sources, dimensions and limitations: [handoff](../../docs/art/kaohsiung/README.md).

Use Swift 6.4, warnings-as-errors and tools/train-models. Independent units:
kaohsiung-{dm1,t,dm2}{,-far}; assembly.json uses +X front, +Y left, Z0 rail.
DM1 +21.7525m 0°, T 0m 0°, DM2 −21.7525m 180°. Coupling pitch sums to65.45m.

```
tools/train-models/run.sh OUT --ids kaohsiung-dm1,kaohsiung-t,kaohsiung-dm2,kaohsiung-dm1-far,kaohsiung-t-far,kaohsiung-dm2-far --assembly-spec tools/kaohsiung/assembly.json
node tools/train-models/package.mjs OUT
node tools/train-models/audit.mjs OUT
python3 tools/kaohsiung/audit.py OUT
blender -b --python tools/taichung-green/import-glb.py -- OUT
node tools/train-models/render.mjs OUT --time both
node tools/train-models/render.mjs OUT --material clay
node tools/train-models/render.mjs OUT --material silhouette
python3 tools/taichung-green/check-png.py OUT
node tools/train-models/inspect.mjs OUT OUT/index.html
node tools/train-models/browser-check.mjs OUT --report-dir SCRATCH
```

shell.sh OUT adapts the common exporter's lookup to the actual shellOnly recipe;
it does not register shell studies or duplicate an exporter implementation.
Shared importer/PNG checks are geometry-independent and reused without changes.

Dedicated audit: actual 850mm eight tyres at x±6.00/±8.30m, gauge1.435m,
roof HVAC base3.60m, exterior glass centroid rays, gangway coupling planes.
Reject actual pane burial150mm, wheel lift35mm and HVAC lift80mm.
Common audit separately rejects deleted/reversed triangles and assembly shift100mm.
These are display-model thresholds, not engineering tolerances or exhaustive collision.

Revision2: `audit.py OUT --previous TRUE_REVISION1` additionally rejects the real
R1 solid coupler and reversed-side destination, actual socket cap triangles,
front-pane burial150mm and float90mm, and destination solids moved to the wrong side.
Glass rays retain all shell/frame faces and exclude only actual thin wiper rods
inside their precise mechanism envelope; backing must exist within55mm.
Near/far each run independently. These display tolerances are not engineering dimensions.

`compare-fixed.mjs TRUE_BEFORE AFTER OUTPUT` uses the shared native renderer,
fixed union bounds/centre/orthographic metre scale and the same light for each pair,
colour/clay/silhouette front/left/top/isometric, all units and assemblies.

`curate.py RUN FIXED_COMPARISON CLEAN_PRODUCER_CHECKOUT PRODUCER` generates the
transparent native-only before/after sheet, updated source/status and delivery.json,
selecting20 PNGs total. It does not copy the prototype photos. Run deliver.py with
that spec; retain one additional public overview PNG only.
