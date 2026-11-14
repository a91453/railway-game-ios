# Hong Kong's street vehicles (decision 738)

The 3D map's double-decker, minibus and taxi on Hong Kong's map, as the app
bundles them (`RailwayGameApp/Resources/Models/hk-*.m3dmodel`), are the
owner's Causeway Bay street scene's own vehicles
(`a91453/railway-reference-private`,
`Railway/street_scene_reference_clean/source/models/street-agents.glb`: the
`bus`, `minibus` and `car` mesh nodes), converted unchanged by
`tools/glb-to-m3dmodel/bridge.mjs` (Node 22). `Map3DHongKongVehicles` fits
them to their sizes and gives them their paint.

Rebuild, with the reference repository checked out beside this one:

```sh
cd tools/glb-to-m3dmodel && npm ci --ignore-scripts && cd ../hk-vehicles
for v in hk-double-decker hk-minibus hk-taxi; do
  node ../glb-to-m3dmodel/bridge.mjs --manifest $v.manifest.json \
    --output ../../RailwayGameApp/Resources/Models/$v.m3dmodel
done
```

The output is the same to the byte for the same reference commit (the
manifests' `revision`). The source glTF's front is +z (its headlamps), so
the manifests say `"front": "+z"`; its units are metres (the bus 12.1 m,
the minibus 7.0 m, the car 4.4 m).

Licence: the reference is the owner's and authorized for the project
(`CLAUDE.md`). The vehicles carry no texture; the reference names no
licence of its own for them (its OpenStreetMap data keeps its ODbL
attribution, which these models do not use).
