// Scratchpad experiment: decode EXT_meshopt_compression / KHR_mesh_quantization
// with @gltf-transform/core+extensions 4.5.1 and meshoptimizer 1.3.0 (all MIT),
// write a plain glTF 2.0 GLB the existing tools/glb-to-m3dmodel can read.
// Usage: node decode-glb.mjs in.glb out.glb [--model name] [--drop-ktx2]
import { createRequire } from 'node:module';
const require = createRequire(process.env.GLTF_MODULES + '/');
const { NodeIO, Accessor } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const { MeshoptDecoder } = require('meshoptimizer');
const [input, output, ...rest] = process.argv.slice(2);
const opt = { model: null, dropKtx2: rest.includes('--drop-ktx2') };
const mi = rest.indexOf('--model'); if (mi >= 0) opt.model = rest[mi + 1];
const t0 = performance.now();
await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
const doc = await io.read(input);
const root = doc.getRoot();
const tRead = performance.now();
const report = { input, extensionsUsed: root.listExtensionsUsed().map(e => e.extensionName),
  extensionsRequired: root.listExtensionsRequired().map(e => e.extensionName) };
// Keep one model's nodes (street-agents.glb tags each node's extras.model).
if (opt.model) {
  const scene = root.getDefaultScene() ?? root.listScenes()[0];
  for (const node of scene.listChildren()) if (node.getExtras()?.model !== opt.model) node.dispose();
}
// Dequantize: every vertex attribute to float32 (getElement denormalizes normalized ints).
let quantized = 0;
for (const mesh of root.listMeshes()) for (const prim of mesh.listPrimitives()) {
  for (const semantic of prim.listSemantics()) {
    const acc = prim.getAttribute(semantic);
    if (acc.getComponentType() === Accessor.ComponentType.FLOAT) continue;
    if (semantic.startsWith('JOINTS')) continue;
    quantized++;
    const n = acc.getCount(), size = acc.getElementSize(), out = new Float32Array(n * size), el = [];
    for (let i = 0; i < n; i++) { acc.getElement(i, el); out.set(el, i * size); }
    const f = doc.createAccessor().setType(acc.getType()).setArray(out).setBuffer(acc.getBuffer());
    prim.setAttribute(semantic, f);
  }
}
let ktx2 = 0;
for (const tex of root.listTextures()) if (tex.getMimeType() === 'image/ktx2') {
  ktx2++;
  if (opt.dropKtx2) tex.dispose();
}
// Remove what the remaining scene no longer uses (functions' prune() would pull in sharp).
const usedMeshes = new Set(root.listNodes().map(n => n.getMesh()).filter(Boolean));
for (const mesh of root.listMeshes()) if (!usedMeshes.has(mesh)) mesh.dispose();
const usedAcc = new Set(), usedMat = new Set();
for (const mesh of root.listMeshes()) for (const p of mesh.listPrimitives()) {
  for (const s of p.listSemantics()) usedAcc.add(p.getAttribute(s));
  if (p.getIndices()) usedAcc.add(p.getIndices());
  for (const t of p.listTargets()) for (const s of t.listSemantics()) usedAcc.add(t.getAttribute(s));
  if (p.getMaterial()) usedMat.add(p.getMaterial());
}
for (const acc of root.listAccessors()) if (!usedAcc.has(acc)) acc.dispose();
for (const mat of root.listMaterials()) if (!usedMat.has(mat)) mat.dispose();
for (const ext of root.listExtensionsUsed()) {
  const name = ext.extensionName;
  if (name === 'EXT_meshopt_compression' || name === 'KHR_mesh_quantization' ||
      (name === 'KHR_texture_basisu' && opt.dropKtx2)) ext.dispose();
}
// Merge buffers into one (GLB embedded buffer).
const buffers = root.listBuffers(); const main = buffers[0];
for (const acc of root.listAccessors()) acc.setBuffer(main);
for (const b of buffers.slice(1)) b.dispose();
await io.write(output, doc);
const t1 = performance.now();
let tri = 0, verts = 0;
for (const mesh of root.listMeshes()) for (const p of mesh.listPrimitives()) {
  verts += p.getAttribute('POSITION').getCount();
  tri += (p.getIndices()?.getCount() ?? p.getAttribute('POSITION').getCount()) / 3;
}
Object.assign(report, { model: opt.model, meshes: root.listMeshes().length, materials: root.listMaterials().length,
  nodes: root.listNodes().length, vertices: verts, triangles: tri, quantizedAttributesDequantized: quantized,
  ktx2Textures: ktx2, ktx2Dropped: opt.dropKtx2 ? ktx2 : 0,
  remainingRequired: root.listExtensionsRequired().map(e => e.extensionName),
  readMs: Math.round(tRead - t0), totalMs: Math.round(t1 - t0) });
console.log(JSON.stringify(report));
