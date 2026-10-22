# Green three-section tram

The source of truth is `Sources/GamePresentation/Map3DGreenTram.swift`. It builds head, middle, tail, and the static full formation. `Map3DModelPack.standard` registers all four by name. The set is not assigned to a GameCore train type; such assignment needs a separate decision about track pitch and representation of articulated units.

Build with the project's Swift 6.4 toolchain:

```sh
tools/green-tram/export.sh /path/outside/public/repo/green-tram
node tools/green-tram/render.mjs /path/outside/public/repo/green-tram
node tools/green-tram/clay.mjs /path/outside/public/repo/green-tram
node tools/green-tram/verify.mjs /path/outside/public/repo/green-tram
python3 tools/green-tram/verify-png.py /path/outside/public/repo/green-tram
node tools/green-tram/browser-check.mjs /path/outside/public/repo/green-tram
python3 tools/green-tram/bundle.py /path/outside/public/repo/green-tram <actual-public-producer-commit>
```

The exporter writes original `M3DM` models, fully embedded GLB, seven transparent PNGs per model, a WebGL viewer and SHA metadata. Four models are new tram assets; the fifth is the existing project light-rail subject for style comparison. The default camera fits each model, so individual preview PNGs are **not** a same-scale comparison. `previews/style-comparison.png` uses one fixed camera and actual metre coordinates.

Assembly: nominal shell length is 10.88 m, unit centres are x = +11.04, 0, −11.04 m, giving a nominal 0.16 m body gap and about 0.08 m between the actual gangway envelopes. All unit origins are at the centre of their body, ground at z=0 after native conversion, +x to the leading head. No unit is rotated during assembly; the tail recipe has its own cab pointing to −x. It is static geometry, with no wheel, door or pantograph animation.

Reference basis: the owner's four images supplied in chat, all viewed visually; they are not local files and are not bundled. The project scene kit uses an illustrative 11 m light-rail section in `Map3DSceneKitTransport.swift`; this informed the display scale, not an engineering claim. The owner's private `trains-pr901` low-floor rail model was checked for style and provenance only. No source mesh or raw image was copied into the public repository.
