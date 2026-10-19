// Project-authored geometry only. No reference assets or model-library data.
import { Document, NodeIO } from '@gltf-transform/core';
import { EXTMeshoptCompression, KHRMeshQuantization } from '@gltf-transform/extensions';
import { MeshoptEncoder } from 'meshoptimizer';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { convertStatic } from './bridge.mjs';

export const manifest = {
  input: 'static-meshopt.glb', modelId: 'static-fixture', nodes: ['body', 'lamp'], front: '+x',
  units: 'meters', recolorLightPaint: false,
  source: { kind: 'non-ai', reference: 'project:tools/glb-to-m3dmodel/make-static-fixtures.mjs',
    revision: 'fixture-v1', license: 'project-authored test geometry', attribution: 'Railway game contributors' },
};

export async function makeStaticFixture({ compressed = false, quantized = false, format = 'glb' } = {}) {
  const doc = new Document(), buffer = doc.createBuffer();
  const position = doc.createAccessor().setType('VEC3').setBuffer(buffer)
    .setArray(quantized ? new Int16Array([0, 0, 0, 32767, 0, 0, 0, 32767, 32767])
      : new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 1])).setNormalized(quantized);
  const indices = doc.createAccessor().setType('SCALAR').setBuffer(buffer).setArray(new Uint16Array([0, 1, 2]));
  // Normalized vertex colors exercise getElement's integer normalization too.
  const colors = doc.createAccessor().setType('VEC4').setBuffer(buffer)
    .setArray(new Uint8Array([255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255])).setNormalized(true);
  function mesh(name, color) {
    return doc.createMesh(name).addPrimitive(doc.createPrimitive().setAttribute('POSITION', position)
      .setAttribute('COLOR_0', colors).setIndices(indices)
      .setMaterial(doc.createMaterial(name).setBaseColorFactor(color)));
  }
  const body = doc.createNode('body').setMesh(mesh('body', [0.8, 0.8, 0.8, 1])).setTranslation([1, 0, 0]);
  const lamp = doc.createNode('lamp').setMesh(mesh('lamp', [0.1, 0.3, 0.8, 1])).setTranslation([0, 1, 0]);
  const parent = doc.createNode('parent').setTranslation([10, 3, -5]).setScale([2, 3, -1])
    .setRotation([0, Math.SQRT1_2, 0, Math.SQRT1_2]).addChild(body).addChild(lamp);
  const excluded = doc.createNode('excluded').setMesh(mesh('excluded', [1, 0, 0, 1])).setTranslation([999, 0, 0]);
  doc.getRoot().setDefaultScene(doc.createScene().addChild(parent).addChild(excluded));
  if (quantized) doc.createExtension(KHRMeshQuantization).setRequired(true);
  if (compressed) doc.createExtension(EXTMeshoptCompression).setRequired(true);
  await MeshoptEncoder.ready;
  const io = new NodeIO().registerExtensions([EXTMeshoptCompression, KHRMeshQuantization])
    .registerDependencies({ 'meshopt.encoder': MeshoptEncoder });
  return format === 'gltf' ? io.writeJSON(doc) : Buffer.from(await io.writeBinary(doc));
}

async function main() {
  const dir = fileURLToPath(new URL('fixtures/', import.meta.url));
  writeFileSync(resolve(dir, 'static-plain.glb'), await makeStaticFixture());
  writeFileSync(resolve(dir, 'static-meshopt.glb'), await makeStaticFixture({ compressed: true, quantized: true }));
  const json = await makeStaticFixture({ format: 'gltf' });
  writeFileSync(resolve(dir, 'static.gltf'), `${JSON.stringify(json.json, null, 2)}\n`);
  for (const [uri, bytes] of Object.entries(json.resources)) writeFileSync(resolve(dir, uri), bytes);
  writeFileSync(resolve(dir, 'static.manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  const { output } = await convertStatic(resolve(dir, 'static.manifest.json'));
  writeFileSync(resolve(dir, 'static.m3dmodel'), output);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
