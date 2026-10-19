# GLB → `.m3dmodel`

Node 22. The output follows the file table in
`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md` and is read by
`Map3DModelFile`. This tool does not call Meshy or add assets to the App.

```sh
cd tools/glb-to-m3dmodel && npm ci --ignore-scripts
npm test
```

The new static bridge uses the tool's own pinned dependencies. App, SwiftPM
and Xcode do not read or bundle these packages. The original Meshy entry
below still uses only Node's standard library and keeps #803's output bytes.

## Static meshopt GLB and `.gltf` + `.bin`

```sh
# From the repository root, with Node 22 on PATH:
node tools/glb-to-m3dmodel/bridge.mjs \
  --manifest tools/glb-to-m3dmodel/fixtures/static.manifest.json \
  --output /tmp/static.m3dmodel --decoded-output /tmp/static-plain.glb
```

`--decoded-output` is optional: it writes the selected, decoded ordinary GLB
as an inspection/interchange artifact. The bridge itself feeds that GLB into
the same `.m3dmodel` converter. Paths to the manifest and output are relative
to the shell; `input` is relative to the manifest. Example manifest:

```json
{
  "input": "model.gltf",
  "modelId": "building-sample",
  "nodes": ["wall", "roof"],
  "front": "+x",
  "units": "meters",
  "recolorLightPaint": false,
  "source": {
    "kind": "non-ai",
    "reference": "private:owner/repository/path/to/source",
    "revision": "the source repository commit or published dataset version",
    "license": "the actual source license / authorized-use terms",
    "attribution": "the required attribution text"
  }
}
```

- Supports `EXT_meshopt_compression` with the official meshoptimizer decoder
  and `KHR_mesh_quantization`, including normalized integer attributes.
  Attributes become float32 using core's `getElement`; node/ancestor matrices
  remain in place. No `functions`, image processing, or simplification is used.
- `nodes` is a required whitelist of exact **mesh-node names** in the default
  scene (first scene if none is designated). Each name must match once;
  it selects that node's mesh, not its descendants. Parent transforms,
  quaternion rotations, negative/nonuniform scale and repeated mesh instances
  are retained. Unselected meshes, materials and accessors are pruned.
- Choose **either** `units: "meters"` (preserve physical dimensions) **or**
  `lengthMeters: 12` (scale the front axis to that length). There is no default
  bus length. `front` has the same four values as the original entry below.
  Both strategies recenter the model horizontally and put its bottom at z=0.
- `recolorLightPaint` is required. Set **false** for buildings and other
  non-vehicle models to keep light neutral surfaces opaque (alpha 255).
  Set true to use the existing instance-paint heuristic (alpha 0).
- All source fields are required. The header retains the original `asset` /
  `extras`, plus `source` with the manifest settings and SHA-256 of the original
  input **and each external `.bin`**. The bridge neither invents Meshy tasks
  nor adds an `aiGenerated` label. AI-marked inputs must use the Meshy entry.
  A source record is traceability, not an automatic license/adoption approval.
- Only untextured, unskinned static triangle assets are accepted. The **whole
  input**, including nodes not selected, is checked before resource loading:
  images/textures (including KTX2/external images), texture material slots,
  skins, animations, morphs/weights, sparse accessors, non-triangle primitives
  and any extension except the two above are explicitly rejected. Draco needs
  a separately authorized dependency and remains unsupported.
- External buffers must be relative local `.bin` files within the input
  directory (subdirectories allowed); URLs, data URIs, escaping symlinks,
  missing files and truncated buffers are refused. Multiple buffers are merged.
  Output is written only after successful conversion, via an atomic rename;
  refusal preserves an existing output file.
- The existing glow rule is unchanged: node/mesh/material names containing
  `light`, `lamp`, `headlight`, `emissive`, or material emission >0.2 mark the
  triangle as glowing. This includes named vehicle tail lamps.

Fixtures are project-authored geometry, not repackaged reference assets.
`make-static-fixtures.mjs` regenerates the compressed/quantized and ordinary
GLBs, external `.gltf` + `buffer.bin`, example manifest and `static.m3dmodel`.
`npm test` checks exact triangle payload agreement, ancestor transforms,
front/ground/dimensions, colors/paint/glow, source hashes, selection and
refusals (including no output on failure). `Map3DModelFileTests` reads the
committed static `.m3dmodel` alongside the original tiny fixture and bus.

## Original Meshy conversion (compatibility)

This established entry retains embedded texture baking for Meshy models;
the new static bridge above refuses textures. It does not require npm install.

```sh
node tools/glb-to-m3dmodel/convert.mjs \
  --input docs/art/meshy-city-bus-2026-10-18/city-bus.glb \
  --output /tmp/city-bus.m3dmodel --id city-bus
node --test tools/glb-to-m3dmodel/convert.test.mjs
```

`--id` selects `front` and `length_m` in `tools/meshy/models.json`. The bus's
`-x` front rotates to model `+x`; it is scaled to 12 m and its lowest point
is `z=0`. Triangle colors come from 21 interior texture samples and are
reduced to at most eight flat RGBA colors. Light neutral paint uses alpha 0
for the existing instance stripe color; a material named as a light or with
emission uses flag bit 0. Degenerate triangles are removed. glTF's `asset`
and `extras` are kept in the header; when they have no AI identification,
the matching `generated.json` tasks and raw GLB SHA-256 are added.

The converter reads embedded glTF 2.0 GLB triangle meshes, scene node
transforms, ordinary accessors, 8-bit PNG and baseline JPEG. JPEG texture
sampling uses each 8×8 block's mean because the output is flat colored. It
rejects required glTF extensions, sparse accessors, external images,
progressive JPEG and unsupported PNG variants with an explicit error.

The committed `fixtures/tiny.glb` is generated by `make-fixture.mjs`. Its
PNG, two real triangles, one degenerate triangle, headlight material and
translated node check the complete path. Its converted output is also read
by `Map3DModelFileTests` in Swift. The real bus GLB has 1,545 input
triangles; the converter removes two with zero area and writes **1,543
triangles, eight colors** (about 80 KB). The source contains no separate
headlight material, so no bus triangle gets the night glow flag.

## Dependencies and licenses

`package.json` pins the three direct versions; `package-lock.json` pins the
complete five-package tree and integrity hashes. All five installed license
texts were checked; no `@gltf-transform/functions`, sharp, or libvips is used.
Preserve the installed packages' license notices when redistributing them.

| Package | Locked version | License / copyright | Installed notice |
| --- | --- | --- | --- |
| [`@gltf-transform/core`](https://github.com/donmccurdy/glTF-Transform) | 4.5.1 | MIT, © 2024 Don McCurdy | `node_modules/@gltf-transform/core/LICENSE.md` |
| [`@gltf-transform/extensions`](https://github.com/donmccurdy/glTF-Transform) | 4.5.1 | MIT, © 2024 Don McCurdy | `node_modules/@gltf-transform/extensions/LICENSE.md` |
| [`meshoptimizer`](https://github.com/zeux/meshoptimizer) | 1.3.0 | MIT, © 2016–2026 Arseny Kapoulkine | `node_modules/meshoptimizer/LICENSE.md` |
| [`property-graph`](https://github.com/donmccurdy/property-graph) (transitive) | 4.1.0 | MIT, © 2021 Don McCurdy | `node_modules/property-graph/LICENSE` |
| [`ktx-parse`](https://github.com/donmccurdy/ktx-parse) (transitive) | 1.1.0 | MIT, © 2020 Don McCurdy | `node_modules/ktx-parse/LICENSE` |

Reuse follows HANDOFF §3's tools-only approval and the #821 / #820 bridge
experiments. `bridge.mjs` adapts core node/resource cleanup and integer
attribute decoding from the project's research `decode-glb.mjs`; the official
MIT libraries supply glTF IO / extension handling / meshopt decoding.
The owner's street-scene reference provides the real validation input and
node names only; no reference source, model, decoded GLB or converted model
is committed. Its actual conversion measurements belong in the PR.

App adoption remains with the 3D session: asset rights/attribution, style
recombination/palette review and device performance checks still apply.
WorldCover and Hong Kong building adoption are separate follow-ups.
