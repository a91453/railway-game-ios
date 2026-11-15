// The coal bunker of the old brick plants' yards (Map3DSceneryProp
// .coalBunker): the game author's own elevated coal bunker, its old white
// mesh kept and coloured by part with the 3D map's palette (studio trial
// b001, variant B), here given the brick, stone and timber of the
// palette's old plants and converted by tools/glb-to-m3dmodel/bridge.mjs.
//
//   node tools/coal-bunker/build.mjs \
//     [--output RailwayGameApp/Resources/Models/coal-bunker.m3dmodel]
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { convertStatic } from '../glb-to-m3dmodel/bridge.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const args = process.argv.slice(2);
const output = args[0] === '--output' && args[1] ? resolve(args[1])
  : join(root, 'RailwayGameApp/Resources/Models/coal-bunker.m3dmodel');

// The source's materials are named by their palette colour; each becomes
// a colour the 3D map already has (Map3DBuildings.swift).
export const colours = {
  '#C9CCD5': 0xB8735A, // the bin's walls: Map3DPalette.brick, as the old plants' halls
  '#CFCBC2': 0xD3CDC1, // the piers: Map3DPalette.granite
  '#8A9099': 0x8A9099, // the bin floor and the conveyor: steel, as it is
  '#2B2F36': 0x2B2F36, // the coal: as it is
  '#2F6DB5': 0x8E6E52, // the conveyor's ends: timber (the counters' and cable cars' wood)
};

export function recoloured(glb) {
  const length = glb.readUInt32LE(12);
  const json = JSON.parse(glb.toString('utf8', 20, 20 + length));
  for (const material of json.materials) {
    const hex = colours[material.name?.toUpperCase()];
    if (hex === undefined) throw new Error(`coal-bunker: no colour for material ${material.name}`);
    delete material.extensions;
    material.pbrMetallicRoughness = { ...material.pbrMetallicRoughness,
      baseColorFactor: [hex >> 16, (hex >> 8) & 255, hex & 255].map(n => n / 255).concat(1) };
  }
  delete json.extensionsUsed;
  delete json.extensionsRequired;
  let text = Buffer.from(JSON.stringify(json));
  text = Buffer.concat([text, Buffer.alloc((4 - text.length % 4) % 4, 0x20)]);
  const rest = glb.subarray(20 + length);
  const head = Buffer.alloc(20);
  head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(20 + text.length + rest.length, 8);
  head.writeUInt32LE(text.length, 12); head.writeUInt32LE(0x4e4f534a, 16);
  return Buffer.concat([head, text, rest]);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const work = mkdtempSync(join(tmpdir(), 'coal-bunker-'));
  try {
    writeFileSync(join(work, 'coal-bunker.glb'), recoloured(readFileSync(join(here, 'source/b001-b.glb'))));
    const manifest = JSON.parse(readFileSync(join(here, 'manifest.json'), 'utf8'));
    writeFileSync(join(work, 'manifest.json'), JSON.stringify({ ...manifest, input: 'coal-bunker.glb' }));
    const result = await convertStatic(join(work, 'manifest.json'));
    writeFileSync(output, result.output);
    process.stdout.write(`${result.triangles} triangles, ${result.colors} colors -> ${output}\n`);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}
