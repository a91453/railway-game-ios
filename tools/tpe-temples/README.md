# tools/tpe-temples

Decision 725 (`docs/decisions/725.md`): nine of Taipei's temples and a
church on the native 3D map in their own shape, from the Taipei City
Government Department of Civil Affairs' 臺北市宗教建築 3D 模型庫
([data.gov.tw 121136](https://data.gov.tw/dataset/121136), Open Government
Data License, version 1.0). Only the shape is kept: every face is painted in
the game's colours by what part of the building it is; no photo, texture or
texture colour reaches the game.

```sh
sh tools/tpe-temples/fetch.sh /tmp/tpe-kmz            # download, check, unzip
(cd tools/glb-to-m3dmodel && npm ci --ignore-scripts)  # meshoptimizer, pinned there
node tools/tpe-temples/build.mjs /tmp/tpe-kmz/x RailwayGameApp/Resources/Models
```

`build.mjs` writes `tpe-*.m3dmodel` (version 1, no texture) and
`placements.json` (each model's point, triangles, simplifier error and
bounds; not bundled). The app's copies are those files; `Map3DTaipeiTemple`
holds the points.

| File | What it does |
|---|---|
| `fetch.sh` | Downloads the eleven KMZ the recipes read, checks their SHA-256, unzips them. |
| `collada.mjs` | Reads `doc.kml`'s model point and heading, and the SketchUp COLLADA 1.4 (units, Z up, nodes, instanced nodes, triangles and polylists). |
| `textures.mjs` | The colour and coverage under each face (JPEG, PNG, TGA), used only to sort faces and drop clear cut-outs. |
| `orient.mjs` | Before simplifying: drops each face's exported back, winds faces alike across every edge two of them share, then turns each connected piece as a whole to its more open side (rays, by area), since the game lights a face by its winding. |
| `wind.mjs` | After simplifying, the same check on the output's exact corners: winds faces alike across every edge two of them share, each connected piece then turned so its faces open to the sky face up (else by its faces' own majority); a piece that cannot be wound alike all round draws the face from both sides. `Map3DBundledModelFilesTests` checks the result. |
| `recipes.mjs` | Each temple's files, dropped materials, kept area and triangle target; the game's colours for the parts. |
| `build.mjs` | Sorts faces into roof, ridge, wall, column, opening, soffit, paving; simplifies with meshoptimizer; writes the models. |
| `sheet.mjs` | A grid of all models at the game's angle (the PR's overview); the per-model look is `tools/model-look/shoot.mjs`. |

How a face is sorted (`classifier` in `build.mjs`): by its shape first. An
upward face above the recipe's `eave` is roof, and the narrow band along the
top of each roof (faces no more than 2.5 m across, within 0.4 m of the
highest roof within 2 m) is its ridge, together with the cut-out ornaments
standing on it. A downward face is the eaves' underside, an upward face
below the eaves paving. Of the upright faces, a strongly red one is a column
and one much darker than the temple's own walls (under 45% of their median
lightness) is an opening; the colour these two tests read is the mean of
the face's flat piece (its neighbours in the same material and plane), so
the triangles of one wall never split between wall and column. Above the
eaves, an upright face with nothing over it is part of the roof: roof
when most of its material is roof (the upturned tips of the eaves),
ridge ornament when its material is small (under 40 m²) or it is at most
2.5 m tall and stands on a roof (a name board, a dragon's silhouette).

How a face is coloured (`blockColours`): the faces of one part joined by
their edges (walls, columns and doors also by material) are one block,
painted the part's game colour nearest the mean photo colour under the
whole block, then lightened (`pale`: L* taken 35% toward the paving's,
a* and b* kept at 90%, so the colour stays a colour instead of going
grey). A block under 2 m² other than a door takes the colour of the
bigger block it borders most. The simplifier keeps the border between two
colours as a seam, so every face it makes is still one block's colour.

Not in this batch: 保安宮, 關渡宮, the mosque and 青山宮, which the dataset
has only as Google 3D Warehouse exports with unknown authors.
