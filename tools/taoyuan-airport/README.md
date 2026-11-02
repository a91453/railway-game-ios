# 本型配置與專用驗收

來源與限制見 [交接](../../docs/art/taoyuan-airport/README.md)。assembly.json使用通用train-models格式，四／五車近遠各一；無車名特例、無loader修改。

```sh
# Swift 6.4 + Node24 + Chromium + Blender4.3 + Python numpy/Pillow
# Environment-dependent paths, not additional code inputs:
export NODE_GLOBAL=/opt/codex/cua_node/lib/node_modules/
export CHROMIUM_PATH=/usr/bin/chromium
tools/taoyuan-airport/rebuild.sh /absolute/output
tools/taoyuan-airport/render.sh /absolute/output
swift test -Xswiftc -warnings-as-errors --filter 'Map3DTaoyuanAirportTests|Map3DModelTests'
```

`audit.py` reads the final native triangles. It checks real exterior-glass centroid visibility and backing, each of eight tyre envelopes and rail contact/clearance, central roof/HVAC contact. It rejects actual glass moved inward/outward, lifted wheels/HVAC; the final assembly JSON rejects lost baggage, wrong order, double reversal and 100mm misplacement. Common `audit.mjs` additionally rejects missing/flipped faces. This is sampled display validation, not exhaustive collision or engineering certification.

`compare-assembly.swift` independently reads legal final native units through the Swift importer and assembles four complete configurations with independently computed metre centres; every resulting position/colour is compared against JS assembly payloads. The GLB check uses the existing vehicle-neutral loop in `tools/taichung-green/import-glb.py`; no old vehicle geometry or dimensions are taken from it.

`common-scale.mjs` fixes centre=[0,0,1.98], extent=[51.155,1.55,1.98], one camera/light across both complete trains and both LODs. `sheets.py` writes precisely 18 role sheets + 2 complete-train sheets, each containing all seven directions in colour/day/night/clay/silhouette. The public overview uses the common metre frames; role-detail sheets have their own disclosed framing. Full local renders are not all submitted.
