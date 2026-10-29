# Two Kaohsiung low-floor tram studies

Independent CAF Urbos and Alstom Citadis recipes. Source/dimension confidence,
module roles and operating protection: [handoff](../../docs/art/kaohsiung-light-rail/README.md).
No changes to the old tram recipes or operating mappings.

Use Swift6.4, Node22+, Python with NumPy/Pillow, Playwright/Chromium and Blender.
Tools/verification dependencies are local only, not added to the App.

```sh
tools/kaohsiung-light-rail/build.sh /absolute/RUN
for fleet in caf citadis; do
  node tools/train-models/check.mjs /absolute/RUN/$fleet
  node tools/train-models/audit.mjs /absolute/RUN/$fleet
  python3 tools/kaohsiung-light-rail/audit.py /absolute/RUN/$fleet
  blender -b --python tools/taichung-green/import-glb.py -- /absolute/RUN/$fleet
  node tools/train-models/render.mjs /absolute/RUN/$fleet --time both
  node tools/train-models/render.mjs /absolute/RUN/$fleet --material clay
  node tools/train-models/render.mjs /absolute/RUN/$fleet --material silhouette
  python3 tools/taichung-green/check-png.py /absolute/RUN/$fleet
done
tools/kaohsiung-light-rail/compare-assembly.sh /absolute/RUN
node tools/kaohsiung-light-rail/review.mjs /absolute/RUN /absolute/FIXED /absolute/BASELINE_EXPORT
```

The common exporter writes native units; `--assembly-spec` uses the two JSON
contracts. The common GLB packager, topology/missing/reversed triangle probes,
renderer, interactive inspector, browser checker and delivery tool are reused.
The existing Blender importer and PNG decoder are vehicle-independent.
`compare-assembly.swift` independently loads final units through the real native
loader, assembles all four consists with the Swift builder, and compares actual
positions/colors/glass flags against the JS expanded payload.

`audit.py` checks final output, not recipe constants: exterior glass visibility
and inward backing with actual face normals (side walls excluded from backing
rays, no blanket occluder exclusion); four wheels per 1/3/5 bogie module and none
under 2/4, rail contact, floor clearance, actual roof mounting base, all four
joint cross sections, near/far shoulder-skin continuity, module order, direction, placement and embedded unit bytes.
It rejects real window faces buried/floated80mm, tyre lift35mm, roof lift80mm,
and actual assembly order/reversal/100mm placement mutations. The shoulder
ray also rejects the real first far-LOD gap found during silhouette inspection. These are model
acceptance probes, not manufacturer dimensions or exhaustive intersections.
Near/far each run; both envelopes stay within25mm, far<half near and native units
<=15000. Full consists have independent scene budgets; they are legal assemblies.

`review.mjs` calls the shared native renderer with common metre frames across
both fleets, all units, all LODs, all materials. It does not auto-fit each model.
Optional baseline contains the real old `lrt-five-formation` and
`green-tram-formation`; these are *other* protected models, not invented prior
versions of these two first deliveries. The baseline files come from the
actual main checkout, not a re-creation. Raw reference-photo comparisons remain
local because no redistribution permission was assumed.

Protection: export **all IDs from the baseline lock**, not the default exporter
selection (which only includes operating sets/styles), in the clean base and
current checkout. `protect-existing.py BASE CURRENT BASE_LOCK` checks all735
existing native bytes and all vertex-field FNV. It skips no KRTC/tram model.
Baseline `check.mjs` already reports33 unrelated failures (32 inherited hash
mismatches and one existing oversize static TEMU2000 formation). Keep that exact
list, do not rewrite old lock entries or gates. Lock additions are only20 new IDs.

After final source/tool commit, rebuild in a separate producer checkout. Compare
native, assemblies, expanded payloads and GLB bytes (not only manifest constants).
Curate at most20 transparent PNGs per fleet, plus one public combined overview.
Use common `deliver.py` and `browser-check.mjs DELIVERED --report-dir SCRATCH`,
then the assets repository's latest `asset_guard.py` on the staged tree and HEAD.
Do not copy all rendered PNGs, create ZIP/history, or deploy a website.
