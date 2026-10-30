# 45DR1000 / DRC1025 native static study

Scope: the 2006–2008 stainless steel, yellow and orange appearance of DRC1025 in the two dated Commons photographs. The class is **45DR1000** and the car markings are **45DRC**. The reported 36 vehicles comprise DRC1001–1035 and the former DRC1036, now DSC1001. Japanese Nippon Sharyo prototypes DRC1001/1002 preceded Tang Eng assembly of later cars in 1998–99. A single motor car can run alone or in multiple; do not assume a permanently married set. The photographed 1025 is not the accessible every-third-number layout. This model excludes themed liveries, DSC1001 alteration and later fall guards.

Published class envelope: 19.774 m long, 2.690 m wide, 3.890 m high. Bogie centres, wheel diameter, rooftop box positions and side window pitch are **photo estimates**. Wikipedia's article itself warns about weak sources; primary drawings have not been obtained. User attachments show matching DRC1025 but have no supplied provenance or reuse license and are kept out of repositories and outside services. Two independently fetched Commons originals were opened locally; see `sources.json` for authors, dates, licenses and SHA256. Photos are references only, and their pixels are not in the public overview or private model package.

The game already maps `dieselRailcar` to its generic DR1000 set and has SceneKit garage art. This recipe registers only in `Map3DModelPack.studies`; it changes no operating set, `standard` pack, GameCore, saves or fixtures. Both cab ends, short body and window row are independently constructed; no G12 geometry or parts are called. The shape, paint and detail are original matte triangle-color geometry. Linux preview must not be read as Metal or user acceptance.

Rebuild: `tools/train-models/run.sh OUT --ids 45dr1000-drc1025,45dr1000-drc1025-far` from the producer commit in the paired asset README. Then `node tools/train-models/package.mjs OUT`, `node tools/train-models/audit.mjs OUT`, `node tools/train-models/render.mjs OUT --time day`, `node tools/train-models/inspect.mjs OUT OUT/index.html`. Three-car display uses the generic assembly spec in `tools/45dr1000/formation.json`.

Appearance review at fixed metre scale: two side doors, stainless corrugations, paired upper headlights, dark cab glass and central yellow gangway agree with the 2006 photo. The rear arrangement, exact roof ducts, underframe boxes and paint junction on the unseen end lack photographic proof. User acceptance of this producer, operating integration and iOS device behavior remain **UNVERIFIED**.

## Fixed-camera visual comparison

The local `comparison.png` juxtaposes the two licensed originals at left and the common renderer's 19.774 m front/side views at right. It remains outside both repositories because the photos are not required to rebuild the geometry. Clay, silhouette and coloured renders used the same camera, metre scale and day lighting. The reference photographs are oblique and cannot themselves be made same-camera orthographic observations.

| Finding | Evidence |
| --- | --- |
| Matches | Narrow front relative to length; rounded roof shoulder; paired upper lamps; central yellow gangway; lower orange V; side orange waist and yellow upper stripe; two side doors and stainless lower ribs. |
| Does not match fully | Real headlamp bezels, cab glazing corner radii and coupler hoses are finer than this matte low-poly study; the front orange cap and black/yellow pilot pattern are simplified; rooftop radiators are too box-like. |
| Insufficient data | Rear maker plate and any end-to-end asymmetry, precise roof pipe routes, exact underframe engine/generator housings, bogie centres, and the concealed side behind the station sign. |

This comparison is the producer's self-review only. Appearance acceptance by the user remains **UNVERIFIED**.

## Revision 2 — front rebuilt after user feedback

The user said revision 1's front was still far from the real car. That front is **not** an accepted appearance. Revision 1 producer `5ad973d5ee0a1eb5bc015e07065dc3e6119f7280` and private commit `b172056575c93814c7c4c548bba04d7a0d01a2a3` remain the actual before version; its PNGs remain in the private `revision-1/` folder. The new producer and file hashes are recorded in `revision-2/`.

Against the 2006 DRC1025 three-quarter photograph, the replacement front changes the dark glazing from blue-grey square blocks into two wide black rounded cab fields, moves the round lamps inside their upper corners, extends the orange cab brow over the rounded roof shoulder, shapes the yellow gangway and its smaller dark window, puts the lower red markers on round pods, and gives the pilot sloped corners, yellow diagonals, a coupler and hoses. The near model also places a small car-number card in the photographed cab; the far model keeps a simple lamp and matching major colours. These are original native vertex-colour triangles and use no G12 part.

The fixed front camera holds the metre scale and day light constant across revisions. The source is oblique rather than orthographic, so the comparison supports relative locations and colour areas, not exact millimetres. Remaining departures: the black gasket still lacks the real door depth and metal handles, the pilot and air hoses are deliberately sparse at game scale, and the exact unseen rear face and roof hardware are not proven. Producer self-review records these openly; user acceptance of revision 2 is **UNVERIFIED**.

The second front pass narrowed both black cab fields to restore the visible yellow outer margins, added solid angled corner cheeks from the 2.69 m sidewall to the end face, and split the pilot markings into two diagonal bars per side. The paired front render should be read alongside the oblique 2006 source, with the photo perspective and estimated fittings kept explicit. These changes supersede the first revision-2 preview; only the final revision-2 producer is delivered.
