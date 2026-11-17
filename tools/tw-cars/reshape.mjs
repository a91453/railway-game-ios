// Decision 838: Taiwan's street cars (a saloon, an SUV, a one-box van and
// the yellow taxi), from four Kenney Car Kit models (CC0) in the owner's
// reference repository (`Railway/town-scene-reference-clean/source/assets/
// car-kit/Models/GLB_20format/`): each face takes the game's colour for the
// part its texture cell paints (no texture is kept), the cabin's sides in
// glass, the 332-triangle wheels become ten-sided ones, the SUV's soft top
// in the body's colour and the spare wheel on its tailgate gone, the taxi's
// roof sign lit, and the body stretched to the real car's length, width and
// height. Written as static GLBs for tools/glb-to-m3dmodel/bridge.mjs.
//
// usage: node tools/tw-cars/reshape.mjs SOURCE_DIR OUT_DIR
// SOURCE_DIR is the car kit's GLB folder (README.md). Writes OUT_DIR/<id>.glb
// and OUT_DIR/<id>.manifest.json for each car in CARS. Deterministic.
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const [source, out] = process.argv.slice(2);
if (!source || !out) throw new Error('usage: reshape.mjs SOURCE_DIR OUT_DIR');
mkdirSync(out, { recursive: true });

// The game's colours, sRGB bytes (bridge.mjs takes COLOR_0 as it stands).
// `paint` is the street cars' white (Map3DStreetLife.carPaints[0]): the
// game turns exactly this colour into the instance's paint. The rest are
// Map3DStreetModel's own (tyre, trim, glass, steel, headlamp, tailLamp) and
// the taxi sign's white (Map3DHongKongVehicles.roofSign), named `signLamp`
// so bridge.mjs marks it glowing.
const hex = h => [h >> 16 & 255, h >> 8 & 255, h & 255];
export const COLOURS = {
  paint: hex(0xF2F3F1), tyre: hex(0x2B2E34), trim: hex(0x41464F), glass: hex(0x26313D), steel: hex(0x9AA0A8),
  headlamp: hex(0xFFF4D6), tailLamp: hex(0xE0402F), signLamp: hex(0xF4F1E6),
};

/// The part a face of the kit paints, by its texture cell (the colour map
/// is four rows of sixteen gradient columns; a car uses one paint column of
/// the second row and the same dark, bumper, lamp and window cells
/// otherwise): the body's colour, the dark grille and arches, the grey
/// bumpers and sills, the number plate, the windows and the lamps.
function part(u, v) {
  const column = Math.min(Math.floor(u * 16), 15), row = Math.min(Math.floor(v * 4), 3);
  if (row === 1) return 'paint';
  if (row === 2 && (column === 4 || column === 5)) return 'tyre';
  if (row === 2 && (column === 6 || column === 7)) return 'trim';
  if (row === 2 && column >= 10 && column <= 13) return 'steel';
  if (row === 3 && (column === 0 || column === 1)) return 'glass';
  if (row === 3 && (column === 2 || column === 3)) return 'headlamp';
  if (row === 3 && (column === 4 || column === 5)) return 'tailLamp';
  throw new Error(`no part for texture cell ${column}, ${row}`);
}

/// A kit GLB's faces by node: [{ node, p: [[x,y,z]×3], part }], y up, the
/// front +z, the nodes' translations applied (the kit's nodes have no
/// rotation or scale; a child's translation adds to its parent's).
function read(file) {
  const bytes = readFileSync(resolve(source, file));
  const jsonLength = bytes.readUInt32LE(12);
  const json = JSON.parse(bytes.subarray(20, 20 + jsonLength).toString());
  const bin = bytes.subarray(20 + jsonLength + 8);
  const accessor = index => {
    const a = json.accessors[index], view = json.bufferViews[a.bufferView];
    const size = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type];
    const width = { 5126: 4, 5125: 4, 5123: 2, 5121: 1 }[a.componentType];
    const stride = view.byteStride ?? size * width, start = (view.byteOffset ?? 0) + (a.byteOffset ?? 0);
    const read = { 5126: o => bin.readFloatLE(o), 5125: o => bin.readUInt32LE(o), 5123: o => bin.readUInt16LE(o), 5121: o => bin.readUInt8(o) }[a.componentType];
    return Array.from({ length: a.count }, (_, i) => Array.from({ length: size }, (_, k) => read(start + i * stride + k * width)));
  };
  const faces = [];
  const visit = (index, offset) => {
    const node = json.nodes[index];
    if (node.rotation || node.scale || node.matrix) throw new Error(`${file}: node ${node.name} is turned or scaled`);
    const at = (node.translation ?? [0, 0, 0]).map((t, k) => t + offset[k]);
    if (node.mesh !== undefined) {
      for (const primitive of json.meshes[node.mesh].primitives) {
        const transform = json.materials[primitive.material]?.pbrMetallicRoughness?.baseColorTexture?.extensions?.KHR_texture_transform;
        if (transform && (transform.offset || transform.scale || transform.rotation)) throw new Error(`${file}: a moved texture`);
        const p = accessor(primitive.attributes.POSITION), uv = accessor(primitive.attributes.TEXCOORD_0);
        const indices = accessor(primitive.indices).map(i => i[0]);
        for (let t = 0; t < indices.length; t += 3) {
          const corners = [0, 1, 2].map(k => indices[t + k]);
          const u = corners.reduce((s, i) => s + uv[i][0], 0) / 3, v = corners.reduce((s, i) => s + uv[i][1], 0) / 3;
          faces.push({ node: node.name, p: corners.map(i => p[i].map((x, k) => x + at[k])), part: node.name.startsWith('wheel') ? null : part(u, v) });
        }
      }
    }
    for (const child of node.children ?? []) visit(child, at);
  };
  const scene = json.scenes[json.scene ?? 0];
  for (const root of scene.nodes) visit(root, [0, 0, 0]);
  return { faces, sha256: createHash('sha256').update(bytes).digest('hex') };
}

const bounds = points => [0, 1, 2].map(k => [Math.min(...points.map(p => p[k])), Math.max(...points.map(p => p[k]))]);

/// `triangles` of a convex shape round `centre`, each wound to face out.
function outward(triangles, centre) {
  return triangles.map(t => {
    const [a, b, c] = t.p, u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    const m = [0, 1, 2].map(k => (a[k] + b[k] + c[k]) / 3 - centre[k]);
    return n[0] * m[0] + n[1] * m[1] + n[2] * m[2] < 0 ? { ...t, p: [a, c, b] } : t;
  });
}

/// A wheel: a ten-sided tyre across x from `x0` to `x1`, radius `r`, about
/// (y, z); its outer face (towards `outside`, ±1) carries a steel hub
/// 0.62 of its radius, standing 1 cm proud.
function wheel({ x0, x1, y, z, r, outside }) {
  const sides = 10;
  const ring = (x, radius) => Array.from({ length: sides }, (_, i) => {
    const a = (i + 0.5) * 2 * Math.PI / sides;
    return [x, y + Math.cos(a) * radius, z + Math.sin(a) * radius];
  });
  const prism = (xa, xb, radius, part) => {
    const a = ring(xa, radius), b = ring(xb, radius), faces = [];
    for (let i = 0; i < sides; i++) {
      const j = (i + 1) % sides;
      faces.push({ part, p: [a[i], b[j], a[j]] }, { part, p: [a[i], b[i], b[j]] });
      if (i > 0 && i < sides - 1) faces.push({ part, p: [b[0], b[i + 1], b[i]] }, { part, p: [a[0], a[i], a[i + 1]] });
    }
    return outward(faces, [(xa + xb) / 2, y, z]);
  };
  const face = outside > 0 ? x1 : x0;
  return [...prism(x0, x1, r, 'tyre'), ...prism(face - outside * 0.01, face + outside * 0.01, r * 0.62, 'steel')];
}

/// A car from the kit's `file`: stretched to `size` (length along z, width
/// x, height y from the ground, metres; the kit's wheels stand on y 0; the
/// roof sign, where there is one, counted apart: `bodyHeight` is the
/// roof's height in the kit, the sign above it), its wheels redrawn, the
/// nodes `drop` left out.
function car(file, { length, width, height, bodyHeight, roof, glasshouse = false, drop = [] }) {
  const { faces, sha256 } = read(file);
  const body = faces.filter(f => !f.node.startsWith('wheel') && !drop.includes(f.node));
  const [bx, by, bz] = bounds(body.flatMap(f => f.p));
  const scale = [width / (bx[1] - bx[0]), height / (bodyHeight ?? by[1]), length / (bz[1] - bz[0])];
  const middle = [(bx[0] + bx[1]) / 2, 0, (bz[0] + bz[1]) / 2];
  const place = p => p.map((x, k) => (x - middle[k]) * scale[k]);
  // Above `roof` (kit units): the SUV's grey top in the body's colour (a
  // crossover's, not a soft-top's); the taxi's sign, rising above its
  // roof, lit.
  const lowest = f => Math.min(...f.p.map(p => p[1]));
  const highest = f => Math.max(...f.p.map(p => p[1]));
  const own = f => bodyHeight !== undefined && lowest(f) >= bodyHeight - 1e-4 && highest(f) > bodyHeight + 0.01 ? 'signLamp'
    : roof !== undefined && f.part === 'trim' && lowest(f) >= roof ? 'paint' : f.part;
  // `glasshouse`: the cabin's sides above the side windows' sill in glass
  // (the kit's door window is a small pane in a painted side; a real
  // car's side glass runs from the windscreen pillar to the rear one),
  // the mirrors, which stand out farther, kept.
  const normal = ({ p: [a, b, c] }) => {
    const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    return n.map(x => x / (Math.hypot(...n) || 1));
  };
  const centre = f => [0, 1, 2].map(k => f.p.reduce((s, p) => s + p[k], 0) / 3);
  const sidePanes = body.filter(f => f.part === 'glass' && Math.abs(normal(f)[0]) > 0.5);
  const sill = Math.min(...sidePanes.map(lowest)), reach = Math.max(...sidePanes.map(f => Math.abs(centre(f)[0]))) + 0.02;
  const glazed = f => glasshouse && own(f) === 'paint' && Math.abs(normal(f)[0]) > 0.6 && lowest(f) >= sill - 0.01
    && Math.abs(centre(f)[0]) <= reach && own(f) !== 'signLamp';
  const triangles = body.map(f => ({ part: glazed(f) ? 'glass' : own(f), p: f.p.map(place) }));
  const wheelNodes = [...new Set(faces.map(f => f.node).filter(n => n.startsWith('wheel') && !drop.includes(n)))];
  for (const name of wheelNodes) {
    const [wx, wy, wz] = bounds(faces.filter(f => f.node === name).flatMap(f => f.p).map(place));
    const r = (wy[1] - wy[0]) / 2, x = (wx[0] + wx[1]) / 2;
    triangles.push(...wheel({ x0: wx[0], x1: wx[1], y: (wy[0] + wy[1]) / 2, z: (wz[0] + wz[1]) / 2, r, outside: Math.sign(x) }));
  }
  return { triangles, sha256 };
}

export const CARS = {
  // A Corolla Altis-sized saloon (4.63 × 1.78 × 1.44 m), the commonest
  // private car on Taiwan's streets.
  'tw-sedan': { file: 'sedan.glb', length: 4.63, width: 1.78, height: 1.44, glasshouse: true },
  // A Corolla Cross-sized crossover (4.46 × 1.83 × 1.62 m), without the
  // kit's spare wheel on the tailgate.
  'tw-suv': { file: 'suv.glb', length: 4.46, width: 1.83, height: 1.62, roof: 0.75, glasshouse: true, drop: ['wheel-back'] },
  // A one-box van (a Town Ace or a short Hiace: 4.7 × 1.75 × 1.95 m),
  // the shops' and trades' van.
  'tw-van': { file: 'van.glb', length: 4.7, width: 1.75, height: 1.95, glasshouse: true },
  // The yellow taxi: the saloon's body (1.44 m) and its roof sign above.
  'tw-taxi': { file: 'taxi.glb', length: 4.63, width: 1.78, height: 1.44, bodyHeight: 1.3, glasshouse: true },
};

/// A GLB of `triangles` (POSITION, NORMAL, COLOR_0; flat normals), a mesh
/// node for each part (named so bridge.mjs marks the lamps glowing and the
/// glass as glass).
function glb(id, triangles) {
  const parts = [...new Set(triangles.map(t => t.part))].sort();
  const arrays = [], views = [], accessors = [], nodes = [], meshes = [];
  let offset = 0;
  for (const [index, name] of parts.entries()) {
    const own = triangles.filter(t => t.part === name);
    const position = new Float32Array(own.length * 9), normal = new Float32Array(own.length * 9), colour = new Float32Array(own.length * 9);
    own.forEach((t, i) => {
      const [a, b, c] = t.p, u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
      const l = Math.hypot(...n);
      for (let k = 0; k < 3; k++) {
        position.set(t.p[k], i * 9 + k * 3);
        normal.set(n.map(x => x / l), i * 9 + k * 3);
        colour.set(COLOURS[name].map(x => x / 255), i * 9 + k * 3);
      }
    });
    const min = [0, 1, 2].map(k => Math.min(...own.flatMap(t => t.p.map(p => p[k]))));
    const max = [0, 1, 2].map(k => Math.max(...own.flatMap(t => t.p.map(p => p[k]))));
    for (const [k, array] of [position, normal, colour].entries()) {
      arrays.push(Buffer.from(array.buffer));
      views.push({ buffer: 0, byteOffset: offset, byteLength: array.byteLength, target: 34962 });
      offset += array.byteLength;
      accessors.push({ bufferView: views.length - 1, componentType: 5126, count: own.length * 3, type: 'VEC3', ...(k === 0 ? { min, max } : {}) });
    }
    meshes.push({ name, primitives: [{ attributes: { POSITION: index * 3, NORMAL: index * 3 + 1, COLOR_0: index * 3 + 2 }, material: 0 }] });
    nodes.push({ name: `${id}__${name}`, mesh: index });
  }
  const bin = Buffer.concat(arrays);
  const json = {
    asset: { version: '2.0', generator: 'railway-game-ios tools/tw-cars/reshape.mjs', copyright: 'Kenney (www.kenney.nl), CC0 1.0; reshaped by this project' },
    scene: 0, scenes: [{ nodes: nodes.map((_, i) => i) }], nodes, meshes,
    materials: [{ name: 'vertexColour', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 1 } }],
    accessors, bufferViews: views, buffers: [{ byteLength: bin.length }],
  };
  let text = Buffer.from(JSON.stringify(json));
  text = Buffer.concat([text, Buffer.alloc(-text.length % 4 & 3, 0x20)]);
  const header = Buffer.alloc(12), jsonHead = Buffer.alloc(8), binHead = Buffer.alloc(8);
  header.write('glTF', 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(12 + 8 + text.length + 8 + bin.length, 8);
  jsonHead.writeUInt32LE(text.length, 0); jsonHead.write('JSON', 4);
  binHead.writeUInt32LE(bin.length, 0); binHead.write('BIN\0', 4);
  return { bytes: Buffer.concat([header, jsonHead, text, binHead, bin]), nodes: nodes.map(n => n.name) };
}

const hasArea = ({ p: [a, b, c] }) => {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  return Math.hypot(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]) > 1e-9;
};
for (const [id, spec] of Object.entries(CARS)) {
  const { triangles, sha256 } = car(spec.file, spec);
  const kept = triangles.filter(hasArea);
  const { bytes, nodes } = glb(id, kept);
  writeFileSync(resolve(out, id + '.glb'), bytes);
  writeFileSync(resolve(out, id + '.manifest.json'), JSON.stringify({
    input: id + '.glb', modelId: id, nodes, front: '+z', units: 'meters', recolorLightPaint: false,
    source: {
      kind: 'non-ai',
      reference: `private:a91453/railway-reference-private/Railway/town-scene-reference-clean/source/assets/car-kit/Models/GLB_20format/${spec.file} (Kenney Car Kit, sha256 ${sha256}), reshaped by tools/tw-cars/reshape.mjs`,
      revision: 'dcc81adea1287c7f0cbb2648a0931df7b4a09ee8',
      license: 'CC0-1.0',
      attribution: 'Kenney (www.kenney.nl); attribution not required',
    },
  }, null, 1) + '\n');
  console.log(id, kept.length, 'triangles');
}
