import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { accessor, applyMatrix, image, readGlb, scenePrimitives } from './glb.mjs';
import { validateGlb } from './validate.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const defaultModels = resolve(root, 'tools/meshy/models.json');
const defaultGenerated = resolve(root, 'tools/meshy/generated.json');

function directions(front, [x, y, z]) {
  switch (front) {
    case '+x': return [x, -z, y];
    case '-x': return [-x, z, y];
    case '+z': return [z, x, y];
    case '-z': return [-z, -x, y];
    default: throw new Error(`Unknown front direction: ${front}`);
  }
}

function area([a, b, c]) {
  const u = b.map((v, i) => v - a[i]), v = c.map((n, i) => n - a[i]);
  const cross = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  return Math.hypot(...cross) / 2;
}

function textureSample(gltf, material, uv, images) {
  const pbr = material?.pbrMetallicRoughness ?? {}, factor = pbr.baseColorFactor ?? [1, 1, 1, 1];
  const texture = pbr.baseColorTexture;
  if (!texture) return factor.map(n => Math.max(0, Math.min(255, Math.round(n * 255))));
  if (texture.texCoord && texture.texCoord !== 0) throw new Error('GLB: only TEXCOORD_0 is supported');
  const entry = gltf.json.textures?.[texture.index];
  if (!entry) throw new Error('GLB: missing base color texture');
  let bitmap = images.get(entry.source);
  if (!bitmap) { bitmap = image(gltf, entry.source); images.set(entry.source, bitmap); }
  const sampler = gltf.json.samplers?.[entry.sampler] ?? {};
  const wrap = (value, mode) => {
    if (mode === 33071) return Math.max(0, Math.min(1, value));
    if (mode === 33648) return 1 - Math.abs(((value % 2) + 2) % 2 - 1);
    return ((value % 1) + 1) % 1;
  };
  const u = wrap(uv[0], sampler.wrapS), v = wrap(uv[1], sampler.wrapT);
  // glTF UVs address the image from its top-left corner.
  const rgba = bitmap.sample(u * (bitmap.width - 1), v * (bitmap.height - 1));
  return rgba.map((value, i) => Math.max(0, Math.min(255, Math.round(value * factor[i]))));
}

function triangleColor(gltf, material, uvs, vertexColors, images) {
  const result = [0, 0, 0, 0];
  let samples = 0;
  // A regular barycentric grid samples the triangle interior, not just the
  // vertices or centroid. Its 21 points average textures with large patches.
  for (let i = 0; i < 6; i++) for (let j = 0; j < 6 - i; j++) {
    const weights = [(i + 1) / 9, (j + 1) / 9, (7 - i - j) / 9];
    const uv = [0, 1].map(axis => weights.reduce((sum, weight, k) => sum + weight * uvs[k][axis], 0));
    const pixel = textureSample(gltf, material, uv, images);
    for (let channel = 0; channel < 4; channel++) {
      const vertex = weights.reduce((sum, weight, k) => sum + weight * (vertexColors?.[k]?.[channel] ?? 1), 0);
      result[channel] += pixel[channel] * vertex;
    }
    samples++;
  }
  return result.map(value => Math.round(value / samples));
}

function paletteOf(triangles, recolorLightPaint) {
  const colors = triangles.map(t => t.color);
  // A narrow stripe can cover few triangles. Keep chromatic surfaces in
  // their own box before splitting the dominant neutral body/window colors.
  const cool = [], warm = [], neutral = [];
  colors.forEach(([r, g, b], i) => {
    if (b > r + 12 || b > g + 12) cool.push(i);
    else if (r > b + 12 || g > b + 12) warm.push(i);
    else neutral.push(i);
  });
  let boxes = [neutral, cool, warm].filter(box => box.length);
  while (boxes.length < 8) {
    let chosen = -1, channel = 0, range = -1;
    boxes.forEach((box, index) => {
      if (box.length < 2) return;
      for (let c = 0; c < 3; c++) {
        const values = box.map(i => colors[i][c]);
        const span = Math.max(...values) - Math.min(...values);
        if (span > range) { chosen = index; channel = c; range = span; }
      }
    });
    if (chosen < 0 || range === 0) break;
    const sorted = boxes[chosen].sort((a, b) => colors[a][channel] - colors[b][channel] || a - b);
    const middle = Math.floor(sorted.length / 2);
    boxes.splice(chosen, 1, sorted.slice(0, middle), sorted.slice(middle));
  }
  const coolSet = new Set(cool);
  const palette = boxes.map(box => {
    // The triangle average softens a thin painted stripe. Pick the more
    // saturated fifth of a cool box to keep that stripe visible after baking.
    const candidates = coolSet.has(box[0])
      ? [...box].sort((a, b) => (colors[b][2] - colors[b][0]) - (colors[a][2] - colors[a][0])).slice(0, Math.max(1, Math.ceil(box.length / 5)))
      : box;
    return [0, 1, 2].map(c => Math.round(candidates.reduce((sum, i) => sum + colors[i][c], 0) / candidates.length));
  });
  const assignments = Array(colors.length);
  boxes.forEach((box, paletteIndex) => box.forEach(i => { assignments[i] = paletteIndex; }));
  // White/light neutral paint is recolored by the existing vehicle shader.
  // Keep one alpha per palette entry, so the complete output has <=8 RGBA colors.
  const packed = palette.map(([r, g, b]) => {
    const paint = recolorLightPaint && Math.min(r, g, b) >= 180 && Math.max(r, g, b) - Math.min(r, g, b) <= 45;
    return (r | (g << 8) | (b << 16) | ((paint ? 0 : 255) << 24)) >>> 0;
  });
  return { packed, assignments };
}

function provenance(gltf, bytes, modelId, generatedPath, sourceRecord) {
  const { asset, extras } = gltf.json;
  const original = { asset, ...(extras === undefined ? {} : { extras }) };
  if (sourceRecord) return JSON.stringify({ ...original, source: sourceRecord });
  const aiRecord = /meshy|tripo|ai[- ]?generated/i.test(JSON.stringify(original));
  if (aiRecord) return JSON.stringify(original);
  const record = JSON.parse(readFileSync(generatedPath, 'utf8'))[modelId];
  if (!record?.tasks?.length) throw new Error(`No AI identification in GLB and no generated.json tasks for ${modelId}`);
  return JSON.stringify({ ...original, generated: {
    model: modelId,
    tasks: record.tasks,
    credits: record.credits,
    raw_sha256: createHash('sha256').update(bytes).digest('hex'),
  } });
}

export function convert(bytes, { modelId, front, lengthMeters, units, recolorLightPaint = true,
  sourceRecord, generatedPath = defaultGenerated }) {
  if (!modelId || !front || (units !== 'meters' && (!Number.isFinite(lengthMeters) || lengthMeters <= 0))) {
    throw new Error('modelId, front, and a positive lengthMeters are required');
  }
  const gltf = readGlb(bytes), images = new Map(), triangles = [];
  for (const { primitive, matrix, name } of scenePrimitives(gltf)) {
    if ((primitive.mode ?? 4) !== 4) throw new Error('GLB: only triangle primitives are supported');
    const positions = accessor(gltf, primitive.attributes?.POSITION);
    const uvs = primitive.attributes?.TEXCOORD_0 === undefined ? null : accessor(gltf, primitive.attributes.TEXCOORD_0);
    const vertexColors = primitive.attributes?.COLOR_0 === undefined ? null : accessor(gltf, primitive.attributes.COLOR_0);
    const indices = primitive.indices === undefined ? positions.map((_, i) => [i]) : accessor(gltf, primitive.indices);
    if (indices.length % 3) throw new Error('GLB: index count is not divisible by three');
    const material = gltf.json.materials?.[primitive.material];
    if (material?.pbrMetallicRoughness?.baseColorTexture && !uvs) throw new Error('GLB: textured primitive has no UVs');
    for (let i = 0; i < indices.length; i += 3) {
      const ids = indices.slice(i, i + 3).map(row => row[0]);
      if (ids.some(index => !Number.isInteger(index) || index < 0 || index >= positions.length)) throw new Error('GLB: index out of bounds');
      const points = ids.map(index => directions(front, applyMatrix(matrix, positions[index])));
      if (points.some(point => point.some(value => !Number.isFinite(value)))) throw new Error('GLB: nonfinite coordinates');
      if (area(points) < 1e-12) continue;
      const color = triangleColor(gltf, material, ids.map(index => uvs?.[index] ?? [0, 0]),
        vertexColors && ids.map(index => vertexColors[index]), images);
      triangles.push({ points, color, glow: /headlight|lamp|emissive|light/i.test(`${name} ${material?.name ?? ''}`) ||
        (material?.emissiveFactor?.some(value => value > 0.2) ?? false) });
    }
  }
  if (!triangles.length || triangles.length > 15_000) throw new Error(`Unsupported triangle count: ${triangles.length}`);
  const all = triangles.flatMap(t => t.points), min = [0, 1, 2].map(axis => Math.min(...all.map(p => p[axis])));
  const max = [0, 1, 2].map(axis => Math.max(...all.map(p => p[axis])));
  const span = max[0] - min[0];
  if (!(span > 0)) throw new Error('GLB: zero length along its front axis');
  const scale = units === 'meters' ? 1 : lengthMeters / span, cx = (min[0] + max[0]) / 2, cy = (min[1] + max[1]) / 2;
  for (const triangle of triangles) triangle.points = triangle.points.map(([x, y, z]) => [(x - cx) * scale, (y - cy) * scale, (z - min[2]) * scale]);
  const { packed, assignments } = paletteOf(triangles, recolorLightPaint);
  const source = Buffer.from(provenance(gltf, bytes, modelId, generatedPath, sourceRecord), 'utf8');
  if (!source.length || source.length > 1_000_000) throw new Error('Invalid provenance size');
  const padded = Math.ceil(source.length / 4) * 4, output = Buffer.alloc(16 + padded + triangles.length * 52);
  output.write('M3DM', 0, 'ascii');
  output.writeUInt16LE(1, 4);
  output.writeUInt32LE(triangles.length, 8);
  output.writeUInt32LE(source.length, 12);
  source.copy(output, 16);
  triangles.forEach((triangle, i) => {
    const at = 16 + padded + i * 52;
    output.writeUInt32LE(triangle.glow ? 1 : 0, at);
    triangle.points.forEach((point, corner) => {
      const offset = at + 4 + corner * 16;
      point.forEach((value, axis) => output.writeFloatLE(value, offset + axis * 4));
      output.writeUInt32LE(packed[assignments[i]], offset + 12);
    });
  });
  return { output, triangles: triangles.length, colors: new Set(assignments.map(i => packed[i])).size,
    paintTriangles: assignments.filter(i => (packed[i] >>> 24) === 0).length,
    glowingTriangles: triangles.filter(t => t.glow).length };
}

async function cli() {
  const args = process.argv.slice(2), options = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i];
    if (!key?.startsWith('--') || !args[i + 1]) throw new Error('Usage: node convert.mjs --input model.glb --output model.m3dmodel --id model-id [--models models.json] [--generated generated.json]');
    options[key.slice(2)] = args[i + 1];
  }
  if (!options.input || !options.output || !options.id) throw new Error('Input, output, and id are required');
  const models = JSON.parse(readFileSync(options.models ?? defaultModels, 'utf8'));
  const model = models.models?.find(entry => entry.id === options.id);
  if (!model) throw new Error(`Unknown model id: ${options.id}`);
  const input = readFileSync(options.input);
  const checked = await validateGlb(input, options.input);
  const result = convert(input, { modelId: options.id, front: model.front,
    lengthMeters: model.length_m, generatedPath: options.generated ?? defaultGenerated });
  writeFileSync(options.output, result.output);
  process.stdout.write(`glTF-Validator: no errors, ${checked.warnings} warnings, ${checked.infos} infos\n`);
  process.stdout.write(`${options.id}: ${result.triangles} triangles, ${result.colors} colors, ${result.paintTriangles} paint triangles, ${result.glowingTriangles} glowing triangles -> ${options.output}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  cli().catch(error => { console.error(error.message); process.exitCode = 1; });
}
