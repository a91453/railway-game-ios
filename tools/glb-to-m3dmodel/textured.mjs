// Decision 653: a GLB to a textured .m3dmodel (version 2): each corner keeps
// its own normal and its texture's u, v, and the model keeps its one
// base-colour image as its file holds it (PNG or JPEG), or a KTX file made
// from it ahead (ASTC for iPhone, `--texture`). Nothing is baked to a
// palette. `convert.mjs` still writes version 1 as before.
//
// Space: glTF's +y up, right-handed; the model's +x front, +y left, +z up,
// right-handed too. `directions` turns one into the other without a
// mirror, so the triangles keep their winding; a node that mirrors (its
// matrix's determinant negative) has two corners swapped back.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { area, directions, provenance } from './convert.mjs';
import { accessor, applyMatrix, imageBytes, readGlb, scenePrimitives } from './glb.mjs';

export const kinds = { png: 1, jpeg: 2, ktx: 3 };
const signatures = {
  1: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  2: [0xff, 0xd8, 0xff],
  3: [0xab, 0x4b, 0x54, 0x58, 0x20, 0x31, 0x31, 0xbb, 0x0d, 0x0a, 0x1a, 0x0a],
};
// Map3DModelTexture.maximumBytes.
export const maximumTextureBytes = 4 << 20;
const maximumTriangles = 15_000;
const glows = 1, painted = 8;

export function textureKind(bytes) {
  for (const [kind, signature] of Object.entries(signatures)) {
    if (bytes.length > signature.length && signature.every((byte, i) => bytes[i] === byte)) return Number(kind);
  }
  throw new Error('Texture: not a PNG, JPEG or KTX (version 1) file');
}

// The columns of a glTF node matrix's 3 × 3, turned into the cofactor
// matrix: the inverse transpose times the determinant, so normals stay
// at right angles to a stretched surface.
function normalMatrix(m) {
  const a = [[m[0], m[4], m[8]], [m[1], m[5], m[9]], [m[2], m[6], m[10]]];
  const c = (r, k) => {
    const rows = [0, 1, 2].filter(i => i !== r), cols = [0, 1, 2].filter(i => i !== k);
    const minor = a[rows[0]][cols[0]] * a[rows[1]][cols[1]] - a[rows[0]][cols[1]] * a[rows[1]][cols[0]];
    return ((r + k) % 2 ? -1 : 1) * minor;
  };
  const cof = [0, 1, 2].map(r => [0, 1, 2].map(k => c(r, k)));
  const det = a[0][0] * cof[0][0] + a[0][1] * cof[0][1] + a[0][2] * cof[0][2];
  return { cof, det };
}

function turnNormal({ cof, det }, front, n) {
  const v = [0, 1, 2].map(r => Math.sign(det) * (cof[r][0] * n[0] + cof[r][1] * n[1] + cof[r][2] * n[2]));
  const turned = directions(front, v), length = Math.hypot(...turned);
  return length > 1e-12 ? turned.map(value => value / length) : [0, 0, 0];
}

const byte = value => Math.max(0, Math.min(255, Math.round(value * 255)));
const packed = rgba => (byte(rgba[0]) | (byte(rgba[1]) << 8) | (byte(rgba[2]) << 16) | (byte(rgba[3]) << 24)) >>> 0;

function chosenTexture(gltf, material) {
  const slot = material?.pbrMetallicRoughness?.baseColorTexture;
  if (!slot) return null;
  if (slot.texCoord && slot.texCoord !== 0) throw new Error('GLB: only TEXCOORD_0 is supported');
  if (slot.extensions?.KHR_texture_transform) throw new Error('GLB: KHR_texture_transform is unsupported; bake the transform into the UVs');
  const entry = gltf.json.textures?.[slot.index];
  if (!entry || entry.source === undefined) throw new Error('GLB: missing base color texture');
  const sampler = gltf.json.samplers?.[entry.sampler] ?? {};
  return { source: entry.source, wrapS: sampler.wrapS ?? 10497, wrapT: sampler.wrapT ?? 10497 };
}

export function convertTextured(bytes, { modelId, front, lengthMeters, units, sourceRecord, generatedPath, texture: given }) {
  if (!modelId || !front || (units !== 'meters' && (!Number.isFinite(lengthMeters) || lengthMeters <= 0))) {
    throw new Error('modelId, front, and a positive lengthMeters (or units "meters") are required');
  }
  const gltf = readGlb(bytes), triangles = [];
  let source = null;
  for (const { primitive, matrix, name } of scenePrimitives(gltf)) {
    if ((primitive.mode ?? 4) !== 4) throw new Error('GLB: only triangle primitives are supported');
    const attributes = primitive.attributes ?? {};
    const positions = accessor(gltf, attributes.POSITION);
    const normals = attributes.NORMAL === undefined ? null : accessor(gltf, attributes.NORMAL);
    const uvs = attributes.TEXCOORD_0 === undefined ? null : accessor(gltf, attributes.TEXCOORD_0);
    const colours = attributes.COLOR_0 === undefined ? null : accessor(gltf, attributes.COLOR_0);
    const indices = primitive.indices === undefined ? positions.map((_, i) => [i]) : accessor(gltf, primitive.indices);
    if (indices.length % 3) throw new Error('GLB: index count is not divisible by three');
    const material = gltf.json.materials?.[primitive.material];
    const factor = material?.pbrMetallicRoughness?.baseColorFactor ?? [1, 1, 1, 1];
    const chosen = chosenTexture(gltf, material);
    if (chosen) {
      if (!uvs) throw new Error('GLB: textured primitive has no UVs');
      if (source !== null && source !== chosen.source) {
        throw new Error('GLB: more than one base color image; a textured .m3dmodel has one (bake an atlas first)');
      }
      source = chosen.source;
      // The app's sampler repeats; a clamped or mirrored sampler draws the
      // same only while every u, v stays within the image.
      const repeats = chosen.wrapS === 10497 && chosen.wrapT === 10497;
      if (!repeats && uvs.some(([u, v]) => u < 0 || u > 1 || v < 0 || v > 1)) {
        throw new Error('GLB: a clamped or mirrored texture with u, v outside 0…1 is unsupported');
      }
    }
    const turn = normalMatrix(matrix), mirrored = turn.det < 0;
    const glow = /headlight|lamp|emissive|light/i.test(`${name} ${material?.name ?? ''}`) ||
      (material?.emissiveFactor?.some(value => value > 0.2) ?? false);
    for (let i = 0; i < indices.length; i += 3) {
      const ids = indices.slice(i, i + 3).map(row => row[0]);
      if (mirrored) [ids[1], ids[2]] = [ids[2], ids[1]];
      if (ids.some(index => !Number.isInteger(index) || index < 0 || index >= positions.length)) throw new Error('GLB: index out of bounds');
      const points = ids.map(index => directions(front, applyMatrix(matrix, positions[index])));
      if (points.flat().some(value => !Number.isFinite(value))) throw new Error('GLB: nonfinite coordinates');
      if (area(points) < 1e-12) continue;
      const corners = ids.map((index, k) => ({
        point: points[k],
        normal: normals ? turnNormal(turn, front, normals[index]) : [0, 0, 0],
        uv: chosen ? uvs[index] : [0, 0],
        // The texture is tinted by the corner's colour; alpha 255, as the
        // instance's own colour shows through no textured corner.
        colour: packed([0, 1, 2].map(c => factor[c] * (colours?.[index]?.[c] ?? 1)).concat(1)),
      }));
      if (corners.some(corner => [...corner.normal, ...corner.uv].some(value => !Number.isFinite(value)))) {
        throw new Error('GLB: nonfinite normal or UV');
      }
      triangles.push({ corners, flags: (chosen ? painted : 0) | (glow ? glows : 0) });
    }
  }
  if (!triangles.length || triangles.length > maximumTriangles) throw new Error(`Unsupported triangle count: ${triangles.length}`);

  let textureBytes = Buffer.alloc(0), kind = 0;
  if (given) {
    if (source === null) throw new Error('--texture given, but no primitive is textured');
    textureBytes = Buffer.from(given);
    kind = textureKind(textureBytes);
  } else if (source !== null) {
    const { data, mimeType } = imageBytes(gltf, source);
    kind = { 'image/png': kinds.png, 'image/jpeg': kinds.jpeg }[mimeType];
    if (!kind) throw new Error(`GLB: unsupported image type ${mimeType}`);
    textureBytes = Buffer.from(data);
    if (textureKind(textureBytes) !== kind) throw new Error(`GLB: image bytes are not ${mimeType}`);
  }
  if (textureBytes.length > maximumTextureBytes) {
    throw new Error(`Texture is ${textureBytes.length} bytes; at most ${maximumTextureBytes} (make a KTX, ASTC, or a smaller image)`);
  }

  const all = triangles.flatMap(t => t.corners.map(c => c.point));
  const min = [0, 1, 2].map(axis => Math.min(...all.map(p => p[axis])));
  const max = [0, 1, 2].map(axis => Math.max(...all.map(p => p[axis])));
  const span = max[0] - min[0];
  if (!(span > 0)) throw new Error('GLB: zero length along its front axis');
  const scale = units === 'meters' ? 1 : lengthMeters / span, cx = (min[0] + max[0]) / 2, cy = (min[1] + max[1]) / 2;
  for (const t of triangles) for (const c of t.corners) {
    const [x, y, z] = c.point;
    c.point = [(x - cx) * scale, (y - cy) * scale, (z - min[2]) * scale];
  }

  const record = Buffer.from(provenance(gltf, bytes, modelId, generatedPath, sourceRecord), 'utf8');
  if (!record.length || record.length > 1_000_000) throw new Error('Invalid provenance size');
  const pad = n => Math.ceil(n / 4) * 4, header = 24, triangleSize = 4 + 3 * 36;
  const body = header + pad(record.length) + pad(textureBytes.length);
  const output = Buffer.alloc(body + triangles.length * triangleSize);
  output.write('M3DM', 0, 'ascii');
  output.writeUInt16LE(2, 4);
  output.writeUInt32LE(triangles.length, 8);
  output.writeUInt32LE(record.length, 12);
  output.writeUInt32LE(kind, 16);
  output.writeUInt32LE(textureBytes.length, 20);
  record.copy(output, header);
  textureBytes.copy(output, header + pad(record.length));
  triangles.forEach((t, i) => {
    const at = body + i * triangleSize;
    output.writeUInt32LE(t.flags, at);
    t.corners.forEach((c, k) => {
      const offset = at + 4 + k * 36;
      [...c.point, ...c.normal, ...c.uv].forEach((value, j) => output.writeFloatLE(value, offset + j * 4));
      output.writeUInt32LE(c.colour, offset + 32);
    });
  });
  return { output, triangles: triangles.length, textureKind: kind, textureBytes: textureBytes.length,
    paintedTriangles: triangles.filter(t => t.flags & painted).length,
    glowingTriangles: triangles.filter(t => t.flags & glows).length };
}

const usage = 'Usage: node textured.mjs --input model.glb --output model.m3dmodel --id model-id --front +x|-x|+z|-z ' +
  '(--length-m 20 | --units meters) [--source source.json] [--texture model.ktx] [--generated generated.json]';

function cli() {
  const args = process.argv.slice(2), options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!args[i]?.startsWith('--') || !args[i + 1]) throw new Error(usage);
    options[args[i].slice(2)] = args[i + 1];
  }
  if (!options.input || !options.output || !options.id || !options.front) throw new Error(usage);
  const result = convertTextured(readFileSync(options.input), {
    modelId: options.id, front: options.front, units: options.units,
    lengthMeters: options['length-m'] === undefined ? undefined : Number(options['length-m']),
    sourceRecord: options.source ? JSON.parse(readFileSync(options.source, 'utf8')) : undefined,
    generatedPath: options.generated ?? fileURLToPath(new URL('../meshy/generated.json', import.meta.url)),
    texture: options.texture ? readFileSync(options.texture) : undefined,
  });
  writeFileSync(options.output, result.output);
  const name = ['none', 'PNG', 'JPEG', 'KTX'][result.textureKind];
  process.stdout.write(`${options.id}: ${result.triangles} triangles (${result.paintedTriangles} textured, ${result.glowingTriangles} glowing), ` +
    `texture ${name} ${result.textureBytes} bytes -> ${options.output}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { cli(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
