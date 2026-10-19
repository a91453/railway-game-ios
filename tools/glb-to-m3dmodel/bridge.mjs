import { createHash } from 'node:crypto';
import { readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO } from '@gltf-transform/core';
import { EXTMeshoptCompression, KHRMeshQuantization } from '@gltf-transform/extensions';
import { MeshoptDecoder } from 'meshoptimizer';
import { convert } from './convert.mjs';

const supported = new Set(['EXT_meshopt_compression', 'KHR_mesh_quantization']);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const fail = message => { throw new Error(`Static glTF: ${message}`); };
const text = value => typeof value === 'string' && value.trim().length > 0;

function validateManifest(manifest) {
  if (!text(manifest.input) || !text(manifest.modelId)) fail('input and modelId are required');
  if (!['+x', '-x', '+z', '-z'].includes(manifest.front)) fail('front must be +x, -x, +z or -z');
  if (!(manifest.units === 'meters' && manifest.lengthMeters === undefined) &&
      !(manifest.units === undefined && Number.isFinite(manifest.lengthMeters) && manifest.lengthMeters > 0)) {
    fail('choose units: "meters" OR a positive lengthMeters');
  }
  if (!Array.isArray(manifest.nodes) || !manifest.nodes.length || !manifest.nodes.every(text) ||
      new Set(manifest.nodes).size !== manifest.nodes.length) fail('nodes must be a nonempty, unique node-name whitelist');
  if (typeof manifest.recolorLightPaint !== 'boolean') fail('recolorLightPaint must explicitly be true or false');
  const source = manifest.source;
  if (source?.kind !== 'non-ai' || !['reference', 'revision', 'license', 'attribution'].every(key => text(source[key]))) {
    fail('source requires kind: "non-ai", reference, revision, license and attribution; use convert.mjs for Meshy');
  }
}

// Inspect the original JSON before NodeIO can load images or discard unknown
// extension/animation semantics. Refusal applies to the whole input asset.
function inspect(bytes) {
  let json;
  if (bytes.toString('ascii', 0, 4) === 'glTF') {
    if (bytes.length < 20 || bytes.readUInt32LE(4) !== 2 || bytes.readUInt32LE(8) !== bytes.length ||
        bytes.toString('ascii', 16, 20) !== 'JSON' || 20 + bytes.readUInt32LE(12) > bytes.length) fail('invalid GLB container');
    json = JSON.parse(bytes.toString('utf8', 20, 20 + bytes.readUInt32LE(12)));
  } else json = JSON.parse(bytes.toString('utf8'));
  if (json.asset?.version !== '2.0') fail('expected glTF 2.0');
  for (const key of ['skins', 'animations', 'textures', 'images']) if (json[key]?.length) fail(`${key} are unsupported (static, untextured models only)`);
  if (json.nodes?.some(node => node.skin !== undefined)) fail('skin is unsupported');
  if (json.nodes?.some(node => node.weights !== undefined) || json.meshes?.some(mesh => mesh.weights !== undefined ||
      mesh.primitives?.some(p => p.targets?.length))) fail('morph targets/weights are unsupported');
  if (json.meshes?.some(mesh => mesh.primitives?.some(p => (p.mode ?? 4) !== 4))) fail('only triangle primitives are supported');
  if (json.accessors?.some(a => a.sparse)) fail('sparse accessors are unsupported');
  for (const name of [...(json.extensionsUsed ?? []), ...(json.extensionsRequired ?? [])]) {
    if (!supported.has(name)) fail(`unsupported extension ${name}`);
  }
  function inspectObjects(value) {
    if (!value || typeof value !== 'object') return;
    for (const name of Object.keys(value.extensions ?? {})) if (!supported.has(name)) fail(`unsupported extension ${name}`);
    for (const [key, child] of Object.entries(value)) {
      if (key.endsWith('Texture') && child && typeof child === 'object') fail('texture material slots are unsupported');
      if (key !== 'extras' && key !== 'extensions') inspectObjects(child);
    }
  }
  inspectObjects(json);
  if (/meshy|tripo|ai[- ]?generated/i.test(JSON.stringify({ asset: json.asset, extras: json.extras }))) {
    fail('AI identification conflicts with non-ai source; use convert.mjs for Meshy');
  }
  return json;
}

function externalBufferPath(input, uri) {
  if (!text(uri) || /[?#]/.test(uri) || /^[a-z][a-z\d+.-]*:/i.test(uri) || isAbsolute(uri)) fail('only local relative .bin buffers are supported');
  const name = decodeURIComponent(uri);
  if (!name.endsWith('.bin')) fail('external buffers must be .bin files');
  const base = realpathSync(dirname(input)), path = realpathSync(resolve(base, name));
  const rel = relative(base, path);
  if (rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel)) fail('external .bin must stay within the input directory');
  return path;
}

export async function convertStatic(manifestPath) {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  validateManifest(manifest);
  const input = resolve(dirname(manifestPath), manifest.input), raw = readFileSync(input), original = inspect(raw);
  const files = [{ uri: manifest.input, sha256: sha256(raw) }];
  const resources = {};
  for (const buffer of original.buffers ?? []) if (buffer.uri !== undefined) {
    const bytes = readFileSync(externalBufferPath(input, buffer.uri));
    if (bytes.length < buffer.byteLength) fail(`truncated external buffer ${buffer.uri}`);
    resources[buffer.uri] = new Uint8Array(bytes);
    files.push({ uri: buffer.uri, sha256: sha256(bytes) });
  }
  await MeshoptDecoder.ready;
  const io = new NodeIO().registerExtensions([EXTMeshoptCompression, KHRMeshQuantization])
    .registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
  // Supply exactly the bytes that were hashed. No network or second file read.
  const jsonDocument = raw.toString('ascii', 0, 4) === 'glTF'
    ? await io.binaryToJSON(new Uint8Array(raw)) : { json: original, resources: {} };
  Object.assign(jsonDocument.resources, resources);
  const doc = await io.readJSON(jsonDocument), root = doc.getRoot();
  const scene = root.getDefaultScene() ?? root.listScenes()[0];
  if (!scene) fail('no scene');
  const active = [];
  scene.traverse(node => { if (node.getMesh()) active.push(node); });
  const selected = new Set();
  for (const name of manifest.nodes) {
    const matches = active.filter(node => node.getName() === name);
    if (matches.length !== 1) fail(`node "${name}" must match exactly one mesh node in the default scene (found ${matches.length})`);
    selected.add(matches[0]);
  }
  // Keep ancestors and their transforms. A name selects that node's mesh,
  // not its descendants. Other scenes and unused resources are not exported.
  for (const other of root.listScenes()) if (other !== scene) other.dispose();
  root.setDefaultScene(scene);
  for (const node of root.listNodes()) if (!selected.has(node)) node.setMesh(null);
  const meshes = new Set([...selected].map(node => node.getMesh()));
  for (const mesh of root.listMeshes()) if (!meshes.has(mesh)) mesh.dispose();
  const accessors = new Set(), materials = new Set();
  for (const mesh of meshes) for (const primitive of mesh.listPrimitives()) {
    for (const semantic of primitive.listSemantics()) accessors.add(primitive.getAttribute(semantic));
    if (primitive.getIndices()) accessors.add(primitive.getIndices());
    if (primitive.getMaterial()) materials.add(primitive.getMaterial());
  }
  for (const acc of root.listAccessors()) if (!accessors.has(acc)) acc.dispose();
  for (const material of root.listMaterials()) if (!materials.has(material)) material.dispose();
  // getElement normalizes integer attributes. Promote to float without functions,
  // preserving quantization node matrices (including nonuniform/negative scale).
  for (const mesh of meshes) for (const primitive of mesh.listPrimitives()) for (const semantic of primitive.listSemantics()) {
    const acc = primitive.getAttribute(semantic);
    if (acc.getComponentType() === 5126) continue;
    const array = new Float32Array(acc.getCount() * acc.getElementSize()), element = [];
    for (let i = 0; i < acc.getCount(); i++) { acc.getElement(i, element); array.set(element, i * acc.getElementSize()); }
    const decoded = doc.createAccessor().setType(acc.getType()).setArray(array).setBuffer(acc.getBuffer());
    primitive.setAttribute(semantic, decoded);
  }
  const used = new Set();
  for (const mesh of meshes) for (const p of mesh.listPrimitives()) {
    for (const s of p.listSemantics()) used.add(p.getAttribute(s));
    if (p.getIndices()) used.add(p.getIndices());
  }
  for (const acc of root.listAccessors()) if (!used.has(acc)) acc.dispose();
  // Both extensions have now been consumed, rather than merely hidden.
  for (const extension of root.listExtensionsUsed()) extension.dispose();
  const buffer = root.listBuffers()[0] ?? doc.createBuffer();
  for (const acc of root.listAccessors()) acc.setBuffer(buffer);
  for (const other of root.listBuffers()) if (other !== buffer) other.dispose();
  const decoded = Buffer.from(await io.writeBinary(doc));
  // writeBinary supplies its own generator: restore the JSON in the GLB without
  // changing accessors, matrices or binary data.
  const decodedJSONLength = decoded.readUInt32LE(12);
  const decodedJSON = JSON.parse(decoded.toString('utf8', 20, 20 + decodedJSONLength));
  decodedJSON.asset = original.asset;
  if (original.extras !== undefined) decodedJSON.extras = original.extras;
  const encodedJSON = Buffer.from(JSON.stringify(decodedJSON)), padded = Buffer.alloc(Math.ceil(encodedJSON.length / 4) * 4, 32);
  encodedJSON.copy(padded);
  const tail = decoded.subarray(20 + decodedJSONLength), head = Buffer.alloc(20);
  head.write('glTF'); head.writeUInt32LE(2, 4); head.writeUInt32LE(20 + padded.length + tail.length, 8);
  head.writeUInt32LE(padded.length, 12); head.write('JSON', 16);
  const plainGlb = Buffer.concat([head, padded, tail]);
  const sourceRecord = { ...manifest.source, files, nodes: manifest.nodes, front: manifest.front,
    ...(manifest.units ? { units: manifest.units } : { lengthMeters: manifest.lengthMeters }),
    recolorLightPaint: manifest.recolorLightPaint };
  return { ...convert(plainGlb, { ...manifest, sourceRecord }), plainGlb };
}

function atomicWrite(path, bytes) {
  const temporary = `${path}.${process.pid}.tmp`;
  try { writeFileSync(temporary, bytes, { flag: 'wx' }); renameSync(temporary, path); }
  finally { rmSync(temporary, { force: true }); }
}

async function cli() {
  const args = process.argv.slice(2), options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--manifest', '--output', '--decoded-output'].includes(args[i]) || !args[i + 1]) fail('usage: node bridge.mjs --manifest model.json --output model.m3dmodel [--decoded-output plain.glb]');
    options[args[i]] = args[i + 1];
  }
  if (!options['--manifest'] || !options['--output']) fail('--manifest and --output are required');
  const result = await convertStatic(resolve(options['--manifest']));
  if (options['--decoded-output']) atomicWrite(options['--decoded-output'], result.plainGlb);
  atomicWrite(options['--output'], result.output);
  console.log(`${result.triangles} triangles, ${result.colors} colors, ${result.paintTriangles} paint triangles, ${result.glowingTriangles} glowing triangles`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await cli(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
