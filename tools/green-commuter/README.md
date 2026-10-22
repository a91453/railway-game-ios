# Green two-car commuter EMU

`Sources/GamePresentation/Map3DGreenCommuter.swift` is the native recipe. It builds distinct outward-facing leading and trailing cab units and a static two-car formation. `Map3DModelPack.standard` registers those three names only; no GameCore train type or route behaviour is changed.

Use Swift 6.4 and rebuild outside the public repository:

```sh
tools/green-commuter/export.sh /path/outside/public/repo/green-commuter
node tools/green-commuter/render.mjs /path/outside/public/repo/green-commuter
node tools/green-commuter/clay.mjs /path/outside/public/repo/green-commuter
node tools/green-commuter/feedback-compare.mjs /path/outside/public/repo/green-commuter /path/to/prior-export
node tools/green-commuter/verify.mjs /path/outside/public/repo/green-commuter
python3 tools/green-commuter/verify-png.py /path/outside/public/repo/green-commuter
node tools/green-commuter/browser-check.mjs /path/outside/public/repo/green-commuter
python3 tools/green-commuter/bundle.py /path/outside/public/repo/green-commuter <actual-public-producer-commit>
```

The exporter creates 3 new native models, 2 existing project style comparisons, 5 embedded GLB and 35 transparent seven-direction PNGs. The WebGL viewer loads native model vertices. Preview PNGs fit each model independently; `previews/style-comparison.png` fixes a single camera in metre coordinates. The optional feedback comparison reads a prior exported native formation and renders both versions with identical metre bounds in left, front and isometric views; it never copies the prior model into the bundle.

Assembly: nominal body length 19.30 m. Unit centres are x=+9.86 and −9.86 m, +x toward the leading cab, with a nominal 0.42 m body gap. No unit is rotated. Both inward ends have gangway faces and couplers; both outward ends have cabs. Each unit has two two-axle bogies, with wheel pairs at local x = ±(6.80 ± 1.02) m. Rail datum is native z=0. This is static geometry without doors, wheels, coupling or pantograph animation.

Reference: the owner's five inline images were visually inspected. No raw image file was locally available or bundled. The project `Map3DTrains` 20 m spacing and 2.9 m car width provide the display scale, not a claim of an identified manufacturer's engineering dimensions. Existing `commuter-cab` and the previous green tram provide game style comparisons; no private source mesh, texture or image was copied into the public repository.
